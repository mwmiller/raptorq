defmodule Raptorq.Generators do
  @moduledoc """
  This module contains functions defined in RFC 6330 for generating
  various required parameters.
  """

  import Bitwise
  import Raptorq.Lookup

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
