defmodule Raptorq.Generators do
  @moduledoc """
  This module contains functions defined in RFC 6330 for generating
  various required parameters.
  """

  import Bitwise
  import Raptorq.Lookup
  alias Raptorq.SIOP

  # Regex cannot be module attributes as of Elixir 1.19
  # This is kept as a "once used variable" for clarity.
  key_re = ~r/(?<i0>\d+)[^\d]+(?<f0>\d+)[^\d]+((?<i1>\d+)[^\d]+(?<f1>\d+))?\s/

  @degrees :code.priv_dir(:raptorq)
           |> Path.join("Deg.table")
           |> File.read!()
           |> String.split("\n", trim: true)
           |> Enum.reduce([], fn line, acc ->
             case Regex.named_captures(key_re, line) do
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

  @doc """
  Generates a Tuple per RFC 6330, Section 5.3.5.4
    Returns { d, a, b, d1, a1, b1}


    ## Parameters
    - `k_prime`: source symbols in the extended source block
    - `x`: an ISI
  """
  def tuple(k_prime, x) when is_integer(k_prime) and is_integer(x) do
    %{j: j, w: w, p1: p1} = SIOP.values_for(k_prime, :exact)
    a_0 = 53591 + j * 997

    a_even =
      case rem(x, 2) do
        0 -> a_0
        _ -> a_0 + 1
      end

    b = 10267 * (j + 1)
    y = rem(b + x * a_even, 2 ** 32)
    v = rand(y, 0, 2 ** 20)
    d = deg(v, k_prime)
    a = 1 + rand(y, 1, w - 1)
    b = rand(y, 2, w)

    d1 =
      case d < 4 do
        true -> 2 + rand(x, 3, 2)
        false -> 2
      end

    a1 = 1 + rand(x, 4, p1 - 1)
    b1 = rand(x, 5, p1)

    {d, a, b, d1, a1, b1}
  end

  def tuple(k_prime, x) do
    raise ArgumentError,
          "Invalid arguments for tuple function. Integer for k_prime (#{k_prime}) and x (#{x})."
  end

  @doc """
    Generates the encoded symbol for a given k_prime and intermediate symbols.
  """
  def enc(k_prime, symbols, {d, a, b, d1, a1, b1}) do
    %{l: l, w: w, p: p, p1: p1} = SIOP.values_for(k_prime, :exact)

    if tuple_size(symbols) != l do
      raise ArgumentError,
            "Invalid arguments for enc function. Tuple size must be equal to l (#{l})."
    end

    pb1 = move_down(b1, a1, p, p1)

    symbols
    |> elem(b)
    |> primary_result(b, a, w, symbols, d - 1)
    |> then(fn res -> res + elem(symbols, w + pb1) end)
    |> secondary_result(pb1, a1, p1, p, w, symbols, d1 - 1)
  end

  # I tried to use a Y-combinator here but it didn't work out.
  defp move_down(b1, _a1, p, _p1) when b1 < p, do: b1

  defp move_down(b1, a1, p, p1) do
    move_down(rem(b1 + a1, p1), a1, p, p1)
  end

  defp primary_result(res, _, _, _, _, 0), do: res

  defp primary_result(res, prev_idx, a, w, symbols, remaining) do
    idx = rem(prev_idx + a, w)
    primary_result(res + elem(symbols, idx), idx, a, w, symbols, remaining - 1)
  end

  defp secondary_result(res, _, _, _, _, _, _, 0), do: res

  defp secondary_result(res, prev_idx, a1, p1, p, w, symbols, remaining) do
    idx = rem(prev_idx + a1, p1) |> move_down(a1, p, p1)
    secondary_result(res + elem(symbols, w + idx), idx, a1, p1, p, w, symbols, remaining - 1)
  end
end
