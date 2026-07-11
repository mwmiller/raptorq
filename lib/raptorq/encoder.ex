defmodule Raptorq.Encoder do
  @moduledoc """
  Compute RaptorQ encoding (repair) symbols from intermediate symbols.

  Per RFC 6330 §5.3.5.3, an encoding symbol for ISI X is the XOR of
  intermediate symbols at column indices given by Tuple[K', X].
  """

  alias Raptorq.{Generators, Octet}

  @doc """
  Compute one encoding symbol for the given K' and ISI.

  `c_syms` is the list of L intermediate symbols (each a binary of
  `symbol_size` bytes).  Returns the encoding symbol.
  """
  def encode_symbol(c_syms, params, isi) do
    %{k: k, w: w, p: p, p1: p1} = params
    sym_size = byte_size(hd(c_syms))
    zero = :binary.copy(<<0>>, sym_size)
    {d, a, b1, d1, a1, b2} = Generators.tuple(k, isi)

    pb1 = move_down(b2, a1, p, p1)

    lt_sum =
      if d > 0 do
        lt_chain_sum(c_syms, b1, a, w, d - 1, Enum.at(c_syms, b1, zero))
      else
        zero
      end

    pi_sum = pi_chain_sum(c_syms, pb1, a1, p, p1, w, d1 - 1, zero)

    Octet.sadd(lt_sum, Octet.sadd(Enum.at(c_syms, w + pb1, zero), pi_sum))
  end

  # ── LT chain ──────────────────────────────────────────────────────────

  defp lt_chain_sum(_syms, _prev, _a, _w, 0, acc), do: acc

  defp lt_chain_sum(syms, prev, a, w, remaining, acc) do
    idx = rem(prev + a, w)
    lt_chain_sum(syms, idx, a, w, remaining - 1, Octet.sadd(acc, Enum.at(syms, idx, <<0>>)))
  end

  # ── PI chain ──────────────────────────────────────────────────────────

  defp pi_chain_sum(_syms, _prev, _a1, _p, _p1, _w, 0, acc), do: acc

  defp pi_chain_sum(syms, prev, a1, p, p1, w, remaining, acc) do
    raw = rem(prev + a1, p1)
    idx = w + move_down(raw, a1, p, p1)
    pi_chain_sum(syms, raw, a1, p, p1, w, remaining - 1, Octet.sadd(acc, Enum.at(syms, idx, <<0>>)))
  end

  # ── PI boundary crossing ──────────────────────────────────────────────

  defp move_down(b1, _a1, p, _p1) when b1 < p, do: b1

  defp move_down(b1, a1, p, p1) do
    move_down(rem(b1 + a1, p1), a1, p, p1)
  end
end
