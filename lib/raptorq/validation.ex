defmodule Raptorq.Validation do
  @moduledoc false

  # Shared input validation for the public API. Programmer errors
  # (bad argument shapes) raise ArgumentError with a clear message
  # instead of failing deep inside the solver.

  @spec data!(term()) :: binary()
  def data!(data) when is_binary(data), do: data

  def data!(data),
    do: raise(ArgumentError, "data must be a binary, got: #{inspect(data)}")

  @spec k!(term()) :: pos_integer()
  def k!(k) when is_integer(k) and k >= 1, do: k

  def k!(k),
    do: raise(ArgumentError, "k must be a positive integer, got: #{inspect(k)}")

  @spec positive!(term(), atom()) :: pos_integer()
  def positive!(value, _name) when is_integer(value) and value >= 1, do: value

  def positive!(value, name),
    do: raise(ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}")

  @spec isi!(term()) :: non_neg_integer()
  def isi!(isi) when is_integer(isi) and isi >= 0, do: isi

  def isi!(isi),
    do: raise(ArgumentError, "isi must be a non-negative integer, got: #{inspect(isi)}")

  @spec data_size!(term()) :: non_neg_integer() | nil
  def data_size!(nil), do: nil

  def data_size!(size) when is_integer(size) and size >= 0, do: size

  def data_size!(size),
    do: raise(ArgumentError, "data_size must be a non-negative integer, got: #{inspect(size)}")

  @spec symbol!(term()) :: binary()
  def symbol!(symbol) when is_binary(symbol) and byte_size(symbol) > 0, do: symbol

  def symbol!(symbol),
    do: raise(ArgumentError, "symbol must be a non-empty binary, got: #{inspect(symbol)}")

  @spec received!(term()) :: [{non_neg_integer(), binary()}]
  def received!(received) when is_list(received) do
    if Enum.all?(received, &valid_pair?/1) do
      received
    else
      raise ArgumentError,
            "received must be a list of {isi, symbol} tuples with non-negative integer " <>
              "isi and non-empty binary symbols"
    end
  end

  def received!(_received),
    do: raise(ArgumentError, "received must be a list of {isi, symbol} tuples")

  defp valid_pair?({isi, symbol}),
    do: is_integer(isi) and isi >= 0 and is_binary(symbol) and byte_size(symbol) > 0

  defp valid_pair?(_), do: false
end
