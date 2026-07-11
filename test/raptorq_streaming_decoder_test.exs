defmodule RaptorqStreamingDecoderTest do
  use ExUnit.Case

  alias Raptorq.StreamingDecoder

  test "streaming decoder accumulates and decodes successfully" do
    data = :crypto.strong_rand_bytes(40)
    k = 10

    {:ok, encoded} = Raptorq.encode(data, k, 4)
    c = Map.get(encoded, :c)
    params = Map.get(encoded, :params)

    # We need k_prime distinct symbols. For k=10, k_prime=10
    needed = params.l - params.s - params.h

    # Create the state
    state = StreamingDecoder.new(k, byte_size(data))
    assert state.needed == needed
    assert state.received_count == 0

    # Add symbols 1 by 1
    state =
      Enum.reduce(0..(needed - 2), state, fn isi, acc_state ->
        sym = Raptorq.repair(c, params, isi)
        assert {:ok, :incomplete, new_state} = StreamingDecoder.add_symbol(acc_state, isi, sym)
        new_state
      end)

    assert state.received_count == needed - 1

    # Adding a duplicate symbol should still return :incomplete
    sym0 = Raptorq.repair(c, params, 0)
    assert {:ok, :incomplete, state_dup} = StreamingDecoder.add_symbol(state, 0, sym0)
    assert state_dup.received_count == needed - 1

    # Add the final needed symbol
    last_isi = needed - 1
    last_sym = Raptorq.repair(c, params, last_isi)

    assert {:ok, {:decoded, decoded_data}, final_state} =
             StreamingDecoder.add_symbol(state, last_isi, last_sym)

    assert decoded_data == data
    assert final_state.received_count == needed
  end

  test "returns error on inconsistent symbol size" do
    state = StreamingDecoder.new(10)

    {:ok, :incomplete, state} = StreamingDecoder.add_symbol(state, 0, <<1, 2, 3, 4>>)

    # Add a symbol with different size
    assert {:error, :inconsistent_symbol_size, _state} =
             StreamingDecoder.add_symbol(state, 1, <<1, 2, 3>>)
  end
end
