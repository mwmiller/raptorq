defmodule RaptorqDecoderTest do
  use ExUnit.Case

  test "full encode-decode round-trip with loss" do
    data = :crypto.strong_rand_bytes(40)
    k = 10

    {:ok, %{c: c, params: params, symbol_size: sym_size}} = Raptorq.encode(data, k)

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

    {:ok, %{c: c, params: params, symbol_size: sym_size}} = Raptorq.encode(data, k)

    needed = params.l - params.s - params.h
    repair_isies = Enum.to_list(1000..(1000 + needed - 1))

    received =
      for isi <- repair_isies do
        {isi, Raptorq.repair(c, params, sym_size, isi)}
      end

    {:ok, decoded} = Raptorq.decode(received, k, byte_size(data))
    assert decoded == data
  end

  test "decode with duplicate ISIs" do
    data = :crypto.strong_rand_bytes(40)
    k = 10

    {:ok, %{c: c, params: params, symbol_size: sym_size}} = Raptorq.encode(data, k)

    # Include duplicate ISIs 1000 twice
    received =
      for isi <- Enum.to_list(1000..1009) do
        {isi, Raptorq.repair(c, params, sym_size, isi)}
      end ++ [{1000, Raptorq.repair(c, params, sym_size, 1000)}]

    assert length(received) == 11

    {:ok, decoded} = Raptorq.decode(received, k, byte_size(data))
    assert decoded == data
  end

  test "insufficient symbols returns error" do
    data = :crypto.strong_rand_bytes(10)
    k = 10

    {:ok, %{c: c, params: params, symbol_size: sym_size}} = Raptorq.encode(data, k)

    # Only 5 symbols instead of K'
    received = for isi <- 0..4, do: {isi, Raptorq.repair(c, params, sym_size, isi)}

    assert {:error, :insufficient_symbols} = Raptorq.decode(received, k)
  end

  test "decoder rejects inconsistent symbol sizes" do
    data = :crypto.strong_rand_bytes(40)
    k = 10

    {:ok, encoded} = Raptorq.encode(data, k)
    c = Map.get(encoded, :c)
    params = Map.get(encoded, :params)
    sym_size = Map.get(encoded, :symbol_size)

    received =
      [{0, Raptorq.repair(c, params, sym_size, 0)} |
       for isi <- Enum.to_list(1000..1009) do
         {isi, Raptorq.repair(c, params, sym_size, isi)}
       end]

    # Replace one symbol with wrong size
    received = List.replace_at(received, 0, {0, <<0, 0, 0>>})
    assert {:error, :inconsistent_symbol_size} = Raptorq.decode(received, k)
  end

  test "K=1 round-trip" do
    data = :crypto.strong_rand_bytes(7)
    k = 1

    {:ok, encoded} = Raptorq.encode(data, k)
    c = Map.get(encoded, :c)
    params = Map.get(encoded, :params)
    sym_size = Map.get(encoded, :symbol_size)

    # Need K' symbols total (need K' = SIOP.values_for(1, :close).k G_ENC rows)
    needed = params.l - params.s - params.h

    received =
      for isi <- Enum.to_list(0..(needed - 1)) do
        {isi, Raptorq.repair(c, params, sym_size, isi)}
      end

    {:ok, decoded} = Raptorq.decode(received, k, byte_size(data))
    assert decoded == data
  end

  test "non-power-of-2 data size" do
    data = :crypto.strong_rand_bytes(37)
    k = 10

    {:ok, encoded} = Raptorq.encode(data, k)
    c = Map.get(encoded, :c)
    params = Map.get(encoded, :params)
    sym_size = Map.get(encoded, :symbol_size)

    needed = params.l - params.s - params.h
    received =
      for isi <- Enum.to_list(1000..(1000 + needed - 1)) do
        {isi, Raptorq.repair(c, params, sym_size, isi)}
      end

    {:ok, decoded} = Raptorq.decode(received, k, byte_size(data))
    assert byte_size(decoded) == 37
    assert decoded == data
  end
end
