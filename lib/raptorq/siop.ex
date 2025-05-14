defmodule Raptorq.SIOP do
  @moduledoc """
  Standard Indices and Other Parameters (SIOP) for RaptorQ.
  """

  # This used to be a module attribute, but Elixir 1.19 deprecates this
  # due to changes in OTP-28 in how regexes are compiled.
  # I only use it once, but I mostly do it for the naming and clarity.
  key_re = ~r/\s(?<k>\d+)\s.*\s(?<j>\d+)\s.*\s(?<s>\d+)\s.*\s(?<h>\d+)\s.*\s(?<w>\d+)\s/

  @value_maps :code.priv_dir(:raptorq)
              |> Path.join("SIOP.table")
              |> File.read!()
              |> String.split("\n", trim: true)
              |> Enum.reduce([], fn line, acc ->
                case Regex.named_captures(key_re, line) do
                  nil ->
                    acc

                  %{"k" => k, "j" => j, "s" => s, "h" => h, "w" => w} ->
                    # Pre-coding relationships from RFC 6330 Section 5.3.3.3
                    ik = String.to_integer(k)
                    ij = String.to_integer(j)
                    is = String.to_integer(s)
                    ih = String.to_integer(h)
                    iw = String.to_integer(w)
                    il = ik + is + ih
                    ip = il - iw
                    [ip1] = Primacy.primes_near(ip, dir: :above, count: 1)
                    iu = ip - ih
                    ib = iw - is

                    [
                      {ik,
                       %{k: ik, j: ij, s: is, h: ih, w: iw, l: il, p: ip, p1: ip1, u: iu, b: ib}}
                      | acc
                    ]
                end
              end)
              |> Enum.reverse()

  @doc """
  Returns the SIOP parameters for a given k value.

  Available strategies:
  - `:exact`: Returns the exact match for k.
  - `:close`: Returns the closest match for k which is greater than or equal to k.
  """
  def values_for(k, strategy \\ :exact) do
    match_fn =
      case strategy do
        :exact -> fn x -> x == k end
        :close -> fn x -> x >= k end
        _ -> fn _ -> false end
      end

    case Enum.find(@value_maps, fn {k_val, _} -> match_fn.(k_val) end) do
      {_, params} ->
        params

      nil ->
        raise(ArgumentError, "No SIOP parameters found for k = #{k} with strategy #{strategy}")
    end
  end
end
