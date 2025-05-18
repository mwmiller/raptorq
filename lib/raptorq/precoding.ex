defmodule Raptorq.Precoding do
  @moduledoc """
  This module provides functions to establish precoding relationships
  """

  alias Raptorq.{SIOP, Octet}

  @doc """
  Establish LDPC precoding relationships.
  """
  def ldpc(symbols, k_prime) do
    %{b: b, s: s, p: p, w: w} = SIOP.values_for(k_prime)

    symbols
    |> sub_tuple(b, s)
    |> ldpc_primary(symbols, s, b, 0)
    |> ldpc_final(symbols, p, w, s, 0)
  end

  defp ldpc_final(d, _c, _p, _w, lim, i) when i == lim, do: d

  defp ldpc_final(d, c, p, w, lim, i) do
    a = rem(i, p)
    b = rem(i + 1, p)
    added = elem(d, i) |> Octet.sadd(elem(c, w + a)) |> Octet.sadd(elem(c, w + b))

    d
    |> tuple_replace(i, added)
    |> ldpc_final(c, p, w, lim, i + 1)
  end

  defp ldpc_primary(d, _c, _s, lim, i) when i == lim, do: d

  defp ldpc_primary(d, c, s, lim, i) when i < lim do
    a = 1 + div(i, s)
    b = rem(i, s)

    d
    |> ldpc_update(b, a, s, c, 0)
    |> ldpc_primary(c, s, lim, i + 1)
  end

  defp ldpc_update(d, b, a, s, c, i) when i < 3 do
    old_symbol = elem(d, b)

    d
    |> tuple_replace(b, Octet.sadd(old_symbol, elem(c, i)))
    |> ldpc_update(rem(b + a, s), a, s, c, i + 1)
  end

  defp ldpc_update(d, _b, _a, _s, _c, _i), do: d

  def sub_tuple(original, start, length) do
    original
    |> Tuple.to_list()
    |> Enum.drop(start)
    |> Enum.take(length)
    |> List.to_tuple()
  end

  defp tuple_replace(tuple, index, value) do
    tuple
    |> Tuple.delete_at(index)
    |> Tuple.insert_at(index, value)
  end
end
