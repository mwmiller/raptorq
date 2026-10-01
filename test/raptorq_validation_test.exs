defmodule RaptorqValidationTest do
  use ExUnit.Case, async: true

  alias Raptorq.StreamingDecoder

  # Local wrappers so invalid arguments reach the runtime validators
  # without tripping compile-time type warnings in Elixir 1.19+.
  defp encode_unchecked(args) do
    case args do
      [data, k] -> Raptorq.encode(data, k)
      [data, k, sym_size] -> Raptorq.encode(data, k, sym_size)
    end
  end

  describe "encode/2 validation" do
    test "raises on non-binary data" do
      assert_raise ArgumentError, ~r/data must be a binary/, fn ->
        encode_unchecked([:not_a_binary, 10])
      end
    end

    test "raises on non-positive k" do
      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        Raptorq.encode(<<1, 2, 3, 4>>, 0)
      end

      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        Raptorq.encode(<<1, 2, 3, 4>>, -5)
      end

      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        encode_unchecked([<<1, 2, 3, 4>>, 2.5])
      end
    end

    test "raises when data length is not a multiple of k" do
      assert_raise ArgumentError, ~r/exact multiple of k/, fn ->
        Raptorq.encode(:crypto.strong_rand_bytes(7), 3)
      end
    end

    test "raises on empty data" do
      assert_raise ArgumentError, ~r/at least k = 10 bytes/, fn ->
        Raptorq.encode(<<>>, 10)
      end
    end

    test "raises when k exceeds the SIOP table" do
      # SIOP table tops out at k = 56,403
      assert_raise ArgumentError, ~r/No SIOP parameters found/, fn ->
        Raptorq.encode(:crypto.strong_rand_bytes(56_404), 56_404)
      end
    end
  end

  describe "encode/3 validation" do
    test "raises when data does not fit k * symbol_size" do
      assert_raise ArgumentError, ~r/does not fit/, fn ->
        Raptorq.encode(:crypto.strong_rand_bytes(41), 5, 8)
      end
    end

    test "raises on non-positive symbol_size" do
      assert_raise ArgumentError, ~r/symbol_size must be a positive integer/, fn ->
        Raptorq.encode(<<1, 2, 3, 4>>, 2, 0)
      end

      assert_raise ArgumentError, ~r/symbol_size must be a positive integer/, fn ->
        Raptorq.encode(<<1, 2, 3, 4>>, 2, -1)
      end
    end

    test "raises on invalid k or data" do
      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        Raptorq.encode(<<1, 2, 3, 4>>, 0, 4)
      end

      assert_raise ArgumentError, ~r/data must be a binary/, fn ->
        encode_unchecked([%{}, 4, 4])
      end
    end

    test "pads short data without truncation loss" do
      assert {:ok, state} = Raptorq.encode(<<1, 2, 3>>, 4, 4)
      assert length(state.source_symbols) == 4
      assert Enum.all?(state.source_symbols, &(byte_size(&1) == 4))
    end
  end

  describe "repair/3 validation" do
    setup do
      {:ok, state} = Raptorq.encode(:crypto.strong_rand_bytes(40), 10)
      %{state: state}
    end

    test "raises on negative isi", %{state: state} do
      assert_raise ArgumentError, ~r/isi must be a non-negative integer/, fn ->
        Raptorq.repair(state.c, state.params, -1)
      end
    end

    test "raises on non-integer isi", %{state: state} do
      assert_raise ArgumentError, ~r/isi must be a non-negative integer/, fn ->
        Raptorq.repair(state.c, state.params, :boom)
      end
    end
  end

  describe "decode/3 validation" do
    test "raises on invalid k" do
      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        Raptorq.decode([{0, <<1, 2, 3, 4>>}], 0)
      end
    end

    test "raises on invalid data_size" do
      assert_raise ArgumentError, ~r/data_size must be a non-negative integer/, fn ->
        Raptorq.decode([{0, <<1, 2, 3, 4>>}], 10, -1)
      end

      assert_raise ArgumentError, ~r/data_size must be a non-negative integer/, fn ->
        Raptorq.decode([{0, <<1, 2, 3, 4>>}], 10, :all)
      end
    end

    test "raises when received is not a list" do
      assert_raise ArgumentError, ~r/received must be a list/, fn ->
        Raptorq.decode(%{}, 10)
      end
    end

    test "raises on malformed received entries" do
      assert_raise ArgumentError, ~r/\{isi, symbol\} tuples/, fn ->
        Raptorq.decode([{0, <<1, 2, 3, 4>>}, {:bad, <<1>>}], 10)
      end

      assert_raise ArgumentError, ~r/\{isi, symbol\} tuples/, fn ->
        Raptorq.decode([{0, <<1, 2, 3, 4>>}, {-1, <<1>>}], 10)
      end

      assert_raise ArgumentError, ~r/\{isi, symbol\} tuples/, fn ->
        Raptorq.decode([{0, <<1, 2, 3, 4>>}, {5, ""}], 10)
      end
    end
  end

  describe "StreamingDecoder validation" do
    test "new/2 raises on invalid arguments" do
      assert_raise ArgumentError, ~r/k must be a positive integer/, fn ->
        StreamingDecoder.new(0)
      end

      assert_raise ArgumentError, ~r/data_size must be a non-negative integer/, fn ->
        StreamingDecoder.new(10, -1)
      end
    end

    test "add_symbol/3 raises on invalid isi or symbol" do
      state = StreamingDecoder.new(10)

      assert_raise ArgumentError, ~r/isi must be a non-negative integer/, fn ->
        StreamingDecoder.add_symbol(state, -1, <<1, 2, 3, 4>>)
      end

      assert_raise ArgumentError, ~r/symbol must be a non-empty binary/, fn ->
        StreamingDecoder.add_symbol(state, 0, <<>>)
      end

      assert_raise ArgumentError, ~r/symbol must be a non-empty binary/, fn ->
        StreamingDecoder.add_symbol(state, 0, 12_345)
      end
    end

    test "returns cached result for symbols added after a successful decode" do
      data = :crypto.strong_rand_bytes(40)
      k = 10
      {:ok, encoded} = Raptorq.encode(data, k)
      needed = encoded.params.l - encoded.params.s - encoded.params.h

      state = StreamingDecoder.new(k, byte_size(data))

      state =
        Enum.reduce(0..(needed - 1), state, fn isi, acc ->
          sym = Raptorq.repair(encoded.c, encoded.params, isi)
          assert {:ok, result, new_state} = StreamingDecoder.add_symbol(acc, isi, sym)
          assert result in [:incomplete, {:decoded, data}]
          new_state
        end)

      # Data already recovered: another symbol returns the cached result
      assert {:ok, {:decoded, ^data}, ^state} =
               StreamingDecoder.add_symbol(state, 9_999, <<0, 0, 0, 0>>)
    end
  end
end
