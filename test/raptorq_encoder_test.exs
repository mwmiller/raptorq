defmodule RaptorqEncoderTest do
  use ExUnit.Case
  alias Raptorq.{ConstraintMatrix, Encoder, Octet}

  @symbol_size 4

  defp build_d_syms(rows, kp, c_syms) do
    start = length(rows) - kp
    enc_rows = Enum.slice(rows, start, kp)
    zero = :binary.copy(<<0>>, @symbol_size)

    Enum.map(enc_rows, fn row ->
      Enum.reduce(row, zero, fn {col, val}, acc ->
        Octet.sadd(acc, Octet.smul(Enum.at(c_syms, col), val))
      end)
    end)
  end

  test "encoding symbol at ISI 0..K-1 matches source symbol" do
    kp = 10
    {rows, params} = ConstraintMatrix.build(kp)
    %{l: l, k: k} = params

    # Random intermediate symbols
    c_syms = for _ <- 1..l, do: :crypto.strong_rand_bytes(@symbol_size)

    # Compute source symbols from constraint matrix G_ENC rows
    source_syms = build_d_syms(rows, kp, c_syms)

    # Verify each encoding symbol matches the corresponding source symbol
    for isi <- 0..(k - 1) do
      enc_sym = Encoder.encode_symbol(c_syms, params, isi)

      assert enc_sym == Enum.at(source_syms, isi),
             "Mismatch at ISI #{isi}: got #{inspect(enc_sym)}, expected #{inspect(Enum.at(source_syms, isi))}"
    end
  end

  test "repair symbol has correct size" do
    kp = 10
    {_rows, params} = ConstraintMatrix.build(kp)
    %{l: l} = params

    c_syms = for _ <- 1..l, do: :crypto.strong_rand_bytes(@symbol_size)

    for isi <- [100, 200, 500, 10_000] do
      enc_sym = Encoder.encode_symbol(c_syms, params, isi)
      assert byte_size(enc_sym) == @symbol_size
    end
  end

  test "full encoding via Raptorq.encode" do
    data = :crypto.strong_rand_bytes(100)
    k = 10

    assert {:ok, %{k_prime: kp, c: c, params: params, source_symbols: src, symbol_size: sz}} =
             Raptorq.encode(data, k)

    assert kp >= k
    assert length(c) == params.l
    assert length(src) == k
    assert sz == 10

    repair = Raptorq.repair(c, params, 999)
    assert byte_size(repair) == 10
  end

  test "encoding symbol for different K' values" do
    for kp <- [10, 56, 150] do
      {_rows, params} = ConstraintMatrix.build(kp)
      %{l: l} = params
      c_syms = for _ <- 1..l, do: :crypto.strong_rand_bytes(@symbol_size)

      enc = Encoder.encode_symbol(c_syms, params, 0)

      assert byte_size(enc) == @symbol_size,
             "K'=#{kp}: encoding symbol size mismatch"
    end
  end
end
