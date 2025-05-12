defmodule Raptorq.Lookup do
  @moduledoc """
    This module provides lookup functions for the RaptorQ encoder and decoder.
    The functions should be largely stable, but the internal implementation
    may change under the hood.
  """
  # I could do some extra magic here to make them match
  # but I don't think it's worth it, and it would reduce flexibility
  for {file, which} <- [
        {"V0.entries", :v0},
        {"V1.entries", :v1},
        {"V2.entries", :v2},
        {"V3.entries", :v3}
      ] do
    @doc """
    Return the value in the #{which} table at the given index.

    Valid indices are in the range 0..255
    """
    def unquote(which)(index)

    :code.priv_dir(:raptorq)
    |> Path.join(file)
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.to_integer/1)
    |> Enum.with_index(fn v, i ->
      def unquote(which)(unquote(i)), do: unquote(v)
    end)

    def unquote(which)(bi), do: raise(ArgumentError, "Invalid index: #{bi}")
  end

  @doc """
  Octet log table lookup.
  Returns an integer in the OCT_LOG table for the provided octet
  <<0>> is expliticly not supported
  """
  # At some point we may want to use more Erlang magic to work with
  # the binary data more directly in these octect tables
  def oct_log(octet)

  :code.priv_dir(:raptorq)
  |> Path.join("OCT_LOG.entries")
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.map(&String.to_integer/1)
  |> Enum.with_index(fn v, i ->
    def oct_log(<<unquote(i + 1)>>), do: unquote(v)
  end)

  def oct_log(bi), do: raise(ArgumentError, "Invalid octect: #{bi}")

  @doc """
  Octet exp table lookup.
  Returns the octect in the OCT_EXP table at the given index.
  Valid indices are in the range 0..509
  """
  def oct_exp(index)

  :code.priv_dir(:raptorq)
  |> Path.join("OCT_EXP.entries")
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.map(&String.to_integer/1)
  |> Enum.with_index(fn v, i ->
    def oct_exp(unquote(i)), do: <<unquote(v)>>
  end)

  def oct_exp(bi), do: raise(ArgumentError, "Invalid index: #{bi}")
end
