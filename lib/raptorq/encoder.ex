defmodule Raptorq.Encoder do
  @moduledoc """
  Compute RaptorQ encoding (repair) symbols from intermediate symbols C.

  Per RFC 6330 §5.3.5.3, an encoding symbol for ISI X is the XOR of
  the intermediate symbols at column indices produced by Tuple[K', X]:

      Enc[K', X] = C[b] + C[b+a] + ... + C[w+pb1] + C[w+pb1+a1] + ...

  where the LT chain walks the first `d` indices by step `a` modulo `w`,
  and the PI chain walks `d1` indices by step `a1` modulo `p1` with
  boundary-crossing via `move_down`.
  """

  alias Raptorq.{Generators, Octet}

  @doc """
  Compute one encoding symbol for the given intermediate symbols,
  SIOP parameters, and ISI.

  Returns the encoding symbol as a binary (same byte size as a C symbol).
  """
  def encode_symbol([first | _] = c_syms, params, isi) do
    %{k: k, w: w, p: p, p1: p1} = params
    sym_size = byte_size(first)
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
