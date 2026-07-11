defmodule RaptorqDecoderTest do
  use ExUnit.Case

  test "full encode-decode round-trip with loss" do
    data = :crypto.strong_rand_bytes(40)
    k = 10

    {:ok, encoded} = Raptorq.encode(data, k)
    c = Map.get(encoded, :c)
    params = Map.get(encoded, :params)
    sym_size = Map.get(encoded, :symbol_size)

    # Lose first 5 source symbols (ISI 0..4), keep 5..9 plus 10 repair symbols
    received =
      for isi <- [5, 6, 7, 8, 9] ++ Enum.to_list(1000..1009) do
        {isi, Raptorq.repair(c, params, sym_size, isi)}
      end

    {:ok, decoded} = Raptorq.decode(received, k, byte_size(data))
    assert decoded == data
  end

  test "decode with only repair symbols" do
    data = :crypto.strong_rand_bytes(100)
    k = 10

    {:ok, encoded} = Raptorq.encode(data, k)
    c = Map.get(encoded, :c)
    params = Map.get(encoded, :params)
    sym_size = Map.get(encoded, :symbol_size)

    needed = params.l - params.s - params.h
    repair_isies = Enum.to_list(1000..(1000 + needed - 1))

    received =
      for isi <- repair_isies do
        {isi, Raptorq.repair(c, params, sym_size, isi)}
      end

    {:ok, decoded} = Raptorq.decode(received, k, byte_size(data))
    assert decoded == data
  end
end
