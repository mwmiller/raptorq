defmodule Raptorq.Decoder do
  @moduledoc """
  Decode received RaptorQ encoding symbols back to source data.

  Given at least L received encoding symbols (ISI + value pairs), rebuilds
  the constraint matrix and solves for intermediate symbols C, then
  extracts the original K source symbols.
  """

  alias Raptorq.{ConstraintMatrix, Solver, Encoder, SIOP, Generators}

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
      enc_rows = build_enc_rows_for_isis(params, Enum.map(selected, fn {isi, _} -> isi end))

      # Full constraint matrix = LDPC + HDPC + ENC rows
      all_rows = ldpc_hdpc ++ enc_rows

      # Build D vector: S+H zeros + received symbol values
      sym_size = selected |> hd() |> elem(1) |> byte_size()
      zero = :binary.copy(<<0>>, sym_size)
      d_syms = List.duplicate(zero, s + h) ++ Enum.map(selected, fn {_, sym} -> sym end)

      # Solve A*C = D
      case Solver.solve(all_rows, params, d_syms) do
        {:ok, c_syms} ->
          # Reconstruct first K source symbols
          source = reconstruct_source(c_syms, params, k, sym_size)

          data = Enum.reduce(source, <<>>, &(&2 <> &1))

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

  defp build_enc_rows_for_isis(params, isis) do
    %{k: kp, w: w, p: p, p1: p1} = params

    Enum.map(isis, fn isi ->
      {d, a, b, d1, a1, b1} = Generators.tuple(kp, isi)

      pb1 = move_down(b1, a1, p, p1)

      lt_cols =
        if d > 0 do
          lt_indices(b, a, w, d)
        else
          []
        end

      pi_cols = [w + pb1 | pi_indices(pb1, a1, p, p1, w, d1 - 1)]

      (lt_cols ++ pi_cols)
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn col, acc -> Map.put(acc, col, <<1>>) end)
    end)
  end

  defp lt_indices(b, _a, _w, 1), do: [b]
  defp lt_indices(b, a, w, remaining), do: [b | lt_indices(rem(b + a, w), a, w, remaining - 1)]

  defp pi_indices(_prev, _a1, _p, _p1, _w, 0), do: []

  defp pi_indices(prev, a1, p, p1, w, remaining) do
    raw = rem(prev + a1, p1)
    [w + move_down(raw, a1, p, p1) | pi_indices(raw, a1, p, p1, w, remaining - 1)]
  end

  defp move_down(b1, _a1, p, _p1) when b1 < p, do: b1

  defp move_down(b1, a1, p, p1) do
    move_down(rem(b1 + a1, p1), a1, p, p1)
  end

  defp reconstruct_source(c_syms, params, k, _sym_size) do
    for isi <- 0..(k - 1), do: Encoder.encode_symbol(c_syms, params, isi)
  end
end
