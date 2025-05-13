defmodule Raptorq.Generators do
  @moduledoc """
  This module contains functions defined in RFC 6330 for generating
  various required parameters.
  """

  import Bitwise
  import Raptorq.Lookup
  alias Raptorq.SIOP

  @key_re ~r/(?<i0>\d+)[^\d]+(?<f0>\d+)[^\d]+((?<i1>\d+)[^\d]+(?<f1>\d+))?\s/
  @degrees :code.priv_dir(:raptorq)
           |> Path.join("Deg.table")
           |> File.read!()
           |> String.split("\n", trim: true)
           |> Enum.reduce([], fn line, acc ->
             case Regex.named_captures(@key_re, line) do
               # Last line special case
               %{"i0" => i0, "f0" => f0, "i1" => "", "f1" => ""} ->
                 [{String.to_integer(f0), String.to_integer(i0)} | acc]

               %{"i0" => i0, "f0" => f0, "i1" => i1, "f1" => f1} ->
                 [
                   {String.to_integer(f0), String.to_integer(i0)},
                   {String.to_integer(f1), String.to_integer(i1)}
                   | acc
                 ]

               _ ->
                 acc
             end
           end)
           |> Enum.sort(:desc)

  @doc """
  Generate the degrees for a given value and k_prime.

  Note that the RFC formulation suggests that it depends only on `v` but
  then uses `k_prime` to limit the maximum value.

  This uses `:exact` value matching for `k_prime`.

  ## Parameters
  - `v`: Non-negative integer between 0 and 1,048,576 (2^20)
  - `k_prime`: Non-negative integer in the SIOP table
  """

  def deg(v, k_prime)
      when is_integer(v) and v >= 0 and v <= 1_048_576 and is_integer(k_prime) do
    {_, dtable} = Enum.find(@degrees, {0, 0}, fn {f, _} -> v >= f end)
    # This will raise on improper k_prime so we can just match
    %{w: w} = SIOP.values_for(k_prime, :exact)
    min(dtable, w - 2)
  end

  def deg(v, k_prime) do
    raise ArgumentError,
          "Invalid arguments for deg function. Integer for v on 0..2^20 (#{v}) and k_prime (#{k_prime})."
  end

  @doc """
  Generates a number between 0 and m-1

    ## Parameters
    - `y`: Non-negative integer
    - `i`: Non-negative integer less than 256
    - `m`: Positive integer limit for the random number generation.

  """
  def rand(y, i, m)

  def rand(y, i, m)
      when is_integer(y) and y >= 0 and is_integer(i) and i >= 0 and i < 256 and is_integer(m) and
             m > 0 do
    # Laid out to match the RFC 6330 specification
    # Not especially for efficiency.
    x0 = rem(y + i, 2 ** 8)
    x1 = rem(div(y, 2 ** 8) + i, 2 ** 8)
    x2 = rem(div(y, 2 ** 16) + i, 2 ** 8)
    x3 = rem(div(y, 2 ** 24) + i, 2 ** 8)

    v0(x0) |> bxor(v1(x1)) |> bxor(v2(x2)) |> bxor(v3(x3)) |> rem(m)
  end

  def rand(y, i, m) do
    raise ArgumentError,
          "Invalid arguments for rand function. Non-negative integer for y (#{y}), i in 0..255 (#{i}) and a positive integer for m (#{m})."
  end
end
