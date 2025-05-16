defmodule Raptorq.Octet do
  @moduledoc """
  Functions to operate on octets and symbols
  """
  import Bitwise

  @doc """
  Add two octects

  iex> Raptorq.Octet.oadd(<<254>>, <<2>>)
  <<252>>
  """
  # I dislike using a guard here, but it shuts up the
  # compiler about the unused variable.
  def oadd(<<u>>, <<v>>) when u == v, do: <<0>>
  def oadd(<<u>>, <<v>>), do: <<bxor(u, v)>>
  def oadd(u, v), do: raise(ArgumentError, "Invalid octet: #{u} or #{v}")

  @doc """
  Subtract two octects
  Eqivalent to oaddition

  iex> Raptorq.Octet.osub(<<1>>, <<1>>)
  <<0>>
  """

  def osub(u, v), do: oadd(u, v)

  @doc """
  Multiply two octets

  iex> Raptorq.Octet.omul(<<255>>, <<1>>)
  <<255>>
  """
  def omul(_, <<0>>), do: <<0>>
  def omul(<<0>>, _), do: <<0>>
  def omul(u, v), do: oexp(olog(u) + olog(v))

  @doc """
  Divide two octets
  iex> Raptorq.Octet.odiv(<<255>>, <<2>>)
  <<241>>
  """
  def odiv(_, <<0>>), do: raise(ArgumentError, "Division by zero")
  def odiv(<<0>>, _), do: <<0>>
  def odiv(u, v), do: oexp(olog(u) - olog(v) + 255)

  @doc """
  Octet olog table lookup.
  Returns an integer in the OCT_LOG table for the provided octet
  <<0>> is expliticly not supported

  iex> Raptorq.Octet.olog(<<127>>)
  87
  """
  def olog(octet)

  :code.priv_dir(:raptorq)
  |> Path.join("OCT_LOG.entries")
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.map(&String.to_integer/1)
  |> Enum.with_index(fn v, i ->
    def olog(<<unquote(i + 1)>>), do: unquote(v)
  end)

  def olog(bi), do: raise(ArgumentError, "Invalid octect: #{bi}")

  @doc """
  Octet exp table lookup.
  Returns the octect in the OCT_EXP table at the given index.
  Valid indices are in the range 0..509

  iex> Raptorq.Octet.oexp(42)
  <<181>>
  """
  def oexp(index)

  :code.priv_dir(:raptorq)
  |> Path.join("OCT_EXP.entries")
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.map(&String.to_integer/1)
  |> Enum.with_index(fn v, i ->
    def oexp(unquote(i)), do: <<unquote(v)>>
  end)

  def oexp(bi), do: raise(ArgumentError, "Invalid index: #{bi}")

  @doc """
  Add two symbols

  iex> Raptorq.Octet.sadd(<<1, 2, 3>>, <<4, 5, 6>>)
  <<5, 7, 5>>
  """
  def sadd(s1, s2) when byte_size(s1) == byte_size(s2) do
    rsadd(s1, s2, <<>>)
  end

  def sadd(s1, s2), do: raise(ArgumentError, "Symbols must be same size: #{s1}, #{s2}")

  def rsadd(<<>>, <<>>, acc), do: acc

  def rsadd(<<a::binary-size(1), rest1::binary>>, <<b::binary-size(1), rest2::binary>>, acc) do
    rsadd(rest1, rest2, acc <> oadd(a, b))
  end

  @doc """
  Multiply a symbol by an octet

  iex> Raptorq.Octet.smul(<<1, 2, 3>>, <<2>>)
  <<2, 4, 6>>
  """
  def smul(s, octet) when is_binary(s) and is_binary(octet) and byte_size(octet) == 1 do
    rsmul(s, octet, <<>>)
  end

  def smul(s, octet),
    do: raise(ArgumentError, "Symbol must be binary with single octet scalar: #{s}, #{octet}")

  def rsmul(<<>>, _octet, acc), do: acc

  def rsmul(<<b::binary-size(1), rest::binary>>, s2, acc) do
    rsmul(rest, s2, acc <> omul(b, s2))
  end
end
