defmodule Raptorq.SIOP do
  @moduledoc """
  Standard Indices and Other Parameters (SIOP) for RaptorQ.
  """

  # At this point, I don't know if this is the correct implementation.
  # I mostly want to see it work and see what happens.
  @key_re ~r/\s(?<k>\d+)\s.*\s(?<j>\d+)\s.*\s(?<s>\d+)\s.*\s(?<h>\d+)\s.*\s(?<w>\d+)\s/

  @value_map :code.priv_dir(:raptorq)
             |> Path.join("SIOP.table")
             |> File.read!()
             |> String.split("\n", trim: true)
             |> Enum.reduce(%{}, fn line, acc ->
               case Regex.named_captures(@key_re, line) do
                 nil ->
                   acc

                 %{"k" => k, "j" => j, "s" => s, "h" => h, "w" => w} ->
                   Map.merge(acc, %{
                     String.to_integer(k) => %{
                       j: String.to_integer(j),
                       s: String.to_integer(s),
                       h: String.to_integer(h),
                       w: String.to_integer(w),
                       k: String.to_integer(k)
                     }
                   })
               end
             end)

  # This appear reptitive, but I want to maintian flexibility
  # and I don't want to use macros for this until I am sure
  @doc """
  Returns the J value for the given K' value.
  """
  def j(k_prime) do
    case Map.get(@value_map, k_prime) do
      %{j: j} -> j
      nil -> raise(ArgumentError, "Invalid k: #{k_prime}")
    end
  end

  @doc """
  Returns the S value for the given K' value.
  """
  def s(k_prime) do
    case Map.get(@value_map, k_prime) do
      %{s: s} -> s
      nil -> raise(ArgumentError, "Invalid k: #{k_prime}")
    end
  end

  @doc """
  Returns the H value for the given K' value.
  """
  def h(k_prime) do
    case Map.get(@value_map, k_prime) do
      %{h: h} -> h
      nil -> raise(ArgumentError, "Invalid k: #{k_prime}")
    end
  end

  @doc """
  Returns the W value for the given K' value.
  """
  def w(k_prime) do
    case Map.get(@value_map, k_prime) do
      %{w: w} -> w
      nil -> raise(ArgumentError, "Invalid k: #{k_prime}")
    end
  end
end
