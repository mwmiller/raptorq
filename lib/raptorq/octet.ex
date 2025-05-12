defmodule Raptorq.Octet do
  @moduledoc """
  Functions to operate on octets.
  """
  import Bitwise
  import Raptorq.Lookup

  @doc """
  Add two octects
  """
  # I dislike using a guard here, but it shuts up the
  # compiler about the unused variable.
  def add(<<u>>, <<v>>) when u == v, do: <<0>>
  def add(<<u>>, <<v>>), do: <<bxor(u, v)>>
  def add(u, v), do: raise(ArgumentError, "Invalid octet: #{u} or #{v}")

  @doc """
  Subtract two octects
  Eqivalent to addition
  """

  def sub(u, v), do: add(u, v)

  @doc """
  Multiply two octets
  """
  def mul(_, <<0>>), do: <<0>>
  def mul(<<0>>, _), do: <<0>>
  def mul(u, v), do: oct_exp(oct_log(u) + oct_log(v))

  @doc """
  Divide two octets
  """
  def div(_, <<0>>), do: raise(ArgumentError, "Division by zero")
  def div(<<0>>, _), do: <<0>>
  def div(u, v), do: oct_exp(oct_log(u) - oct_log(v) + 255)
end
