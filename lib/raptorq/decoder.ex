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

  alias Raptorq.{ConstraintMatrix, Solver, Encoder, SIOP}

  @doc """
  Decode received symbols to recover original source data.

  ## Parameters
    - `received` — list of `{isi, symbol_binary}` tuples
    - `k` — number of source symbols in the original block
    - `data_size` — total byte size of the original source data (optional)

  Returns `{:ok, binary}` with the decoded data, or `{:error, reason}`.
  """
  def decode(received, k, data_size \\ nil) do
    %{k: kp, s: s, h: h, l: l} = params = SIOP.values_for(k, :close)

    received_cnt = length(received)
    needed = l - s - h

    if received_cnt < needed do
      {:error, "Need at least #{needed} encoding symbols, got #{received_cnt}"}
    else
      # Take the first needed ISIs
      selected = Enum.take(received, needed)

      # Build LDPC + HDPC rows
      {fixed_rows, _} = ConstraintMatrix.build(kp)
      ldpc_hdpc = Enum.take(fixed_rows, s + h)

      # Build G_ENC rows for received ISIs
      isis = Enum.map(selected, fn {isi, _} -> isi end)
      enc_rows = ConstraintMatrix.build_enc_rows(params.k, params.w, params.p, params.p1, isis)

      # Full constraint matrix = LDPC + HDPC + ENC rows
      all_rows = ldpc_hdpc ++ enc_rows

      # Build D vector: S+H zeros + received symbol values
      [{_, first_sym} | _] = selected
      sym_size = byte_size(first_sym)
      zero = :binary.copy(<<0>>, sym_size)
      d_syms = List.duplicate(zero, s + h) ++ Enum.map(selected, fn {_, sym} -> sym end)

      # Solve A*C = D
      case Solver.solve(all_rows, params, d_syms) do
        {:ok, c_syms} ->
          # Reconstruct first K source symbols
          source = reconstruct_source(c_syms, params, k, sym_size)

          data = IO.iodata_to_binary(source)

          result =
            if data_size do
              binary_part(data, 0, min(data_size, byte_size(data)))
            else
              data
            end

          {:ok, result}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp reconstruct_source(c_syms, params, k, _sym_size) do
    for isi <- 0..(k - 1), do: Encoder.encode_symbol(c_syms, params, isi)
  end
end
