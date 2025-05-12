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
end
