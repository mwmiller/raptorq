defmodule Raptorq.Decoder do
  @moduledoc """
  Recover source data from received RaptorQ encoding symbols.

  ## Decoding process (RFC 6330 §5.4)

  1. The receiver knows the ISI of each received symbol.
  2. A G_ENC row of the constraint matrix is built per ISI via
     Tuple[K', ISI], and the LDPC+HDPC rows are always present
     (with D = 0).
  3. The system A·C = D is formed and solved for C.
  4. The first K encoding symbols are regenerated from C and
     concatenated to produce the original source data.

  `received` must contain at least K' symbols (the first K' G_ENC
  rows plus the S+H LDPC+HDPC rows give the full L×L system).
  """

  alias Raptorq.{ConstraintMatrix, Encoder, SIOP, Solver}

  @doc """
  Decode received symbols to recover original source data.

  ## Parameters
    - `received` — list of `{isi, symbol_binary}` tuples
    - `k` — number of source symbols in the original block
    - `data_size` — total byte size of the original source data (optional)

  Returns `{:ok, binary}` with the decoded data, or `{:error, reason}`.
  """
  def decode(received, k, data_size \\ nil) do
    %{l: l} = params = SIOP.values_for(k, :close)
    needed = l - params.s - params.h

    with :ok <- validate_count(received, needed),
         {:ok, deduped} <- deduplicate(received),
         :ok <- validate_sizes(deduped) do
      try_subsets(deduped, needed, params, k, data_size)
    end
  end

  # ── Validation ────────────────────────────────────────────────────────

  defp validate_count(received, needed) do
    if length(received) >= needed, do: :ok, else: {:error, :insufficient_symbols}
  end

  defp deduplicate(received) do
    {deduped, _} =
      Enum.reduce(received, {[], MapSet.new()}, fn
        {isi, _sym} = pair, {acc, seen} ->
          if MapSet.member?(seen, isi) do
            {acc, seen}
          else
            {[pair | acc], MapSet.put(seen, isi)}
          end
      end)

    {:ok, Enum.reverse(deduped)}
  end

  defp validate_sizes([]), do: :ok

  defp validate_sizes([{_, first} | rest]) do
    sz = byte_size(first)

    if Enum.all?(rest, fn {_, s} -> byte_size(s) == sz end) do
      :ok
    else
      {:error, :inconsistent_symbol_size}
    end
  end

  # ── Subset selection ──────────────────────────────────────────────────

  defp try_subsets(received, needed, params, k, data_size) do
    # Try two orderings: normal and reversed.
    orderings = [received, Enum.reverse(received)]

    Enum.reduce_while(orderings, {:error, :singular}, fn order, _ ->
      selected = Enum.take(order, needed)
      %{k: kp, s: s, h: h} = params

      {fixed_rows, _} = ConstraintMatrix.build(kp)
      ldpc_hdpc = Enum.take(fixed_rows, s + h)

      {isis, syms} = Enum.unzip(selected)
      enc_rows = ConstraintMatrix.build_enc_rows(params.k, params.w, params.p, params.p1, isis)

      all_rows = ldpc_hdpc ++ enc_rows

      [{_, first_sym} | _] = selected
      sym_size = byte_size(first_sym)
      zero = :binary.copy(<<0>>, sym_size)
      d_syms = List.duplicate(zero, s + h) ++ syms

      case Solver.solve(all_rows, params, d_syms) do
        {:ok, c_syms} ->
          source = reconstruct_source(c_syms, params, k)
          data = IO.iodata_to_binary(source)

          result =
            if data_size do
              binary_part(data, 0, min(data_size, byte_size(data)))
            else
              data
            end

          {:halt, {:ok, result}}

        {:error, reason} ->
          {:cont, {:error, reason}}
      end
    end)
  end

  defp reconstruct_source(c_syms, params, k) do
    for isi <- 0..(k - 1), do: Encoder.encode_symbol(c_syms, params, isi)
  end
end
