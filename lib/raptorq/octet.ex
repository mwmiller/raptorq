defmodule Raptorq.Octet do
  @moduledoc """
  Functions to operate on octets.
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
end
