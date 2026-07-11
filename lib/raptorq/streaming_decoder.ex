defmodule Raptorq.StreamingDecoder do
  @moduledoc """
  A streaming stateful decoder that accumulates symbols as they arrive
  and attempts to decode once enough symbols are available.

  ## Example

      state = Raptorq.StreamingDecoder.new(10, 40)
      
      {:ok, :incomplete, state} = Raptorq.StreamingDecoder.add_symbol(state, 0, sym0)
      # ... accumulate more symbols ...
      {:ok, {:decoded, data}, state} = Raptorq.StreamingDecoder.add_symbol(state, 12, sym12)
  """

  alias Raptorq.SIOP

  defstruct [:k, :data_size, :needed, :received, :received_count]

  @doc """
  Initialize a new streaming decoder for a block of `k` source symbols.
  `data_size` is optional and used to truncate padding from the final output.
  """
  def new(k, data_size \\ nil) do
    params = SIOP.values_for(k, :close)
    # The solver needs exactly K' (which is L - S - H) independent symbols
    needed = params.l - params.s - params.h

    %__MODULE__{
      k: k,
      data_size: data_size,
      needed: needed,
      received: %{},
      received_count: 0
    }
  end

  @doc """
  Add a symbol to the decoder state.

  Returns `{:ok, :incomplete, state}` if more symbols are needed (or if the
  system remains singular).
  Returns `{:ok, {:decoded, binary}, state}` if the data was successfully recovered.
  Returns `{:error, reason, state}` if the symbol is invalid (e.g. inconsistent size).
  """
  def add_symbol(%__MODULE__{received: received} = state, isi, _symbol)
      when is_map_key(received, isi) do
    {:ok, :incomplete, state}
  end

  def add_symbol(state, isi, symbol) do
    if valid_size?(state, symbol) do
      do_add_symbol(state, isi, symbol)
    else
      {:error, :inconsistent_symbol_size, state}
    end
  end

  defp valid_size?(%{received_count: 0}, _symbol), do: true

  defp valid_size?(state, symbol) do
    {_first_isi, first_sym} = Enum.at(state.received, 0)
    byte_size(symbol) == byte_size(first_sym)
  end

  defp do_add_symbol(state, isi, symbol) do
    new_received = Map.put(state.received, isi, symbol)
    new_count = state.received_count + 1
    new_state = %{state | received: new_received, received_count: new_count}

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
        {:ok, {:decoded, data}, state}

      {:error, :singular} ->
        # The constraint matrix was singular with this subset of symbols.
        # We need to wait for another symbol to try a different combination.
        {:ok, :incomplete, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end
end
