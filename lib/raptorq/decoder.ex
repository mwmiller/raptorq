defmodule Raptorq.Decoder do
  @moduledoc """
  Recover source data from received RaptorQ encoding symbols.

  ## Decoding process (RFC 6330 §5.4)

  1. The receiver knows the ISI of each received symbol.
  2. A G_ENC row of the constraint matrix is built per ISI via
     Tuple[K', ISI], and the LDPC+HDPC rows are always present
     (with D = 0).
  3. The system A·C = D is formed and solved for C.
  4. The solution is verified against every row of the system — both
     the LDPC/HDPC constraint rows and the received encoding rows.
  5. The first K encoding symbols are regenerated from C and
     concatenated to produce the original source data.

  `received` must contain at least K' distinct symbols (the first K'
  G_ENC rows plus the S+H LDPC+HDPC rows give the full L×L system).

  ## Subset selection and verification

  The system is square, so the result depends on which K' symbols are
  selected.  When more than K' symbols are available, subsets are tried
  as sliding windows over the received symbols (up to a bounded number
  of attempts), including windows over the received symbols in reverse
  order (the 5-phase solver's pivot heuristics are row-order sensitive).

  Every solved system is verified against the full system it was built
  from.  A singular system can otherwise yield a plausible-looking but
  *incorrect* intermediate symbol vector; verification turns that into
  `{:error, :singular}` so callers can try another subset (or wait for
  more symbols, in the streaming case) instead of receiving corrupt
  data.
  """

  alias Raptorq.{ConstraintMatrix, Encoder, SIOP, Solver, Validation}

  # Upper bound on candidate subsets attempted during a single decode.
  # Each attempt is a full L×L solve, so this bounds worst-case time.
  @max_attempts 8

  @typedoc "Reasons returned by `decode/3`."
  @type reason :: :insufficient_symbols | :inconsistent_symbol_size | :singular

  @doc """
  Decode received symbols to recover original source data.

  ## Parameters
    - `received` — list of `{isi, symbol_binary}` tuples
    - `k` — number of source symbols in the original block
    - `data_size` — total byte size of the original source data (optional)

  Returns `{:ok, binary}` with the decoded data, or `{:error, reason}`.
  """
  @spec decode([{non_neg_integer(), binary()}], pos_integer(), non_neg_integer() | nil) ::
          {:ok, binary()} | {:error, reason()}
  def decode(received, k, data_size \\ nil) do
    Validation.k!(k)
    Validation.data_size!(data_size)
    received = Validation.received!(received)

    %{l: l} = params = SIOP.values_for(k, :close)
    needed = l - params.s - params.h

    with {:ok, deduped} <- deduplicate(received),
         :ok <- validate_count(deduped, needed),
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
    received
    |> candidate_subsets(needed)
    |> Enum.reduce_while({:error, :singular}, fn subset, _ ->
      case solve_and_verify(subset, params, k, data_size) do
        {:ok, data} -> {:halt, {:ok, data}}
        {:error, reason} -> {:cont, {:error, reason}}
      end
    end)
  end

  # Sliding windows over the received symbols: window 0 uses the first
  # `needed` symbols, window 1 drops the first and pulls in the next, and
  # so on.  This gives distinct candidate systems whenever extra symbols
  # are available.  Reversed-order windows follow, because the 5-phase
  # solver's pivot heuristics are sensitive to row order: the same symbol
  # set may solve in one order and fail in another.
  defp candidate_subsets(received, needed) do
    forward = Enum.chunk_every(received, needed, 1, :discard)
    backward = received |> Enum.reverse() |> Enum.chunk_every(needed, 1, :discard)

    (forward ++ backward)
    |> Enum.uniq()
    |> Enum.take(@max_attempts)
  end

  defp solve_and_verify(subset, params, k, data_size) do
    %{k: kp, s: s, h: h} = params
    {fixed_rows, _} = ConstraintMatrix.build(kp)
    ldpc_hdpc = Enum.take(fixed_rows, s + h)

    {isis, syms} = Enum.unzip(subset)
    enc_rows = ConstraintMatrix.build_enc_rows(params.k, params.w, params.p, params.p1, isis)

    all_rows = ldpc_hdpc ++ enc_rows

    [{_, first_sym} | _] = subset
    zero = :binary.copy(<<0>>, byte_size(first_sym))
    d_syms = List.duplicate(zero, s + h) ++ syms

    with {:ok, c_syms} <- Solver.solve(all_rows, params, d_syms),
         :ok <- Solver.verify_solution(c_syms, all_rows, d_syms) do
      source = reconstruct_source(c_syms, params, k)
      {:ok, truncate(source, data_size)}
    end
  end

  defp truncate(source, data_size) do
    data = IO.iodata_to_binary(source)

    if data_size do
      binary_part(data, 0, min(data_size, byte_size(data)))
    else
      data
    end
  end

  defp reconstruct_source(c_syms, params, k) do
    for isi <- 0..(k - 1), do: Encoder.encode_symbol(c_syms, params, isi)
  end
end
