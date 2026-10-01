defmodule Raptorq.StreamingDecoder do
  @moduledoc """
  A streaming stateful decoder that accumulates symbols as they arrive
  and attempts to decode once enough symbols are available.

  ## Example

      state = Raptorq.StreamingDecoder.new(10, 40)

      {:ok, :incomplete, state} = Raptorq.StreamingDecoder.add_symbol(state, 0, sym0)
      # ... accumulate more symbols ...
      {:ok, {:decoded, data}, state} = Raptorq.StreamingDecoder.add_symbol(state, 12, sym12)

  Once the data has been recovered, any further `add_symbol/3` calls
  return the cached result immediately.
  """

  alias Raptorq.{SIOP, Validation}

  defstruct [:k, :data_size, :needed, :received, :received_count, :symbol_size, :decoded]

  @typedoc "Decoder state, created with `new/2`."
  @type t :: %__MODULE__{
          k: pos_integer(),
          data_size: non_neg_integer() | nil,
          needed: pos_integer(),
          received: %{optional(non_neg_integer()) => binary()},
          received_count: non_neg_integer(),
          symbol_size: non_neg_integer() | nil,
          decoded: binary() | nil
        }

  @typedoc "Result of `add_symbol/3`."
  @type add_result ::
          {:ok, :incomplete, t()}
          | {:ok, {:decoded, binary()}, t()}
          | {:error, Raptorq.error_reason(), t()}

  @doc """
  Initialize a new streaming decoder for a block of `k` source symbols.
  `data_size` is optional and used to truncate padding from the final output.
  """
  @spec new(pos_integer(), non_neg_integer() | nil) :: t()
  def new(k, data_size \\ nil) do
    Validation.k!(k)
    Validation.data_size!(data_size)

    params = SIOP.values_for(k, :close)
    # The solver needs exactly K' (which is L - S - H) independent symbols
    needed = params.l - params.s - params.h

    %__MODULE__{
      k: k,
      data_size: data_size,
      needed: needed,
      received: %{},
      received_count: 0,
      symbol_size: nil,
      decoded: nil
    }
  end

  @doc """
  Add a symbol to the decoder state.

  Returns `{:ok, :incomplete, state}` if more symbols are needed (or if the
  system remains singular).
  Returns `{:ok, {:decoded, binary}, state}` if the data was successfully
  recovered (cached results are returned for symbols added after a
  successful decode).
  Returns `{:error, reason, state}` if the symbol is invalid (e.g. inconsistent size).

  Raises `ArgumentError` for invalid `isi` or `symbol` arguments.
  """
  @spec add_symbol(t(), non_neg_integer(), binary()) :: add_result()
  def add_symbol(state, isi, symbol)

  def add_symbol(%__MODULE__{decoded: data} = state, _isi, _symbol) when is_binary(data) do
    {:ok, {:decoded, data}, state}
  end

  def add_symbol(%__MODULE__{received: received} = state, isi, _symbol)
      when is_map_key(received, isi) do
    {:ok, :incomplete, state}
  end

  def add_symbol(state, isi, symbol) do
    Validation.isi!(isi)
    Validation.symbol!(symbol)

    if valid_size?(state, symbol) do
      do_add_symbol(state, isi, symbol)
    else
      {:error, :inconsistent_symbol_size, state}
    end
  end

  defp valid_size?(%{symbol_size: nil}, _symbol), do: true
  defp valid_size?(state, symbol), do: byte_size(symbol) == state.symbol_size

  defp do_add_symbol(state, isi, symbol) do
    new_received = Map.put(state.received, isi, symbol)
    new_count = state.received_count + 1

    new_state = %{
      state
      | received: new_received,
        received_count: new_count,
        symbol_size: state.symbol_size || byte_size(symbol)
    }

    if new_count >= state.needed do
      attempt_decode(new_state)
    else
      {:ok, :incomplete, new_state}
    end
  end

  defp attempt_decode(state) do
    received_list = Map.to_list(state.received)

    case Raptorq.decode(received_list, state.k, state.data_size) do
      {:ok, data} ->
        {:ok, {:decoded, data}, %{state | decoded: data}}

      {:error, _reason} ->
        # Singular (or otherwise unresolvable) with the symbols collected
        # so far. Wait for another symbol to try a different subset.
        {:ok, :incomplete, state}
    end
  end
end
