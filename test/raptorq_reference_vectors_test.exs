defmodule Raptorq.ReferenceVectorsTest do
  @moduledoc """
  Cross-validation of the encoder, repair, and decoder against independently
  generated reference vectors.

  Source of the vectors
  ---------------------
  These vectors were extracted from the `raptorq` Rust crate by Christopher
  Berner (https://github.com/cberner/raptorq), version 2.0.1 — the de facto
  reference implementation of RFC 6330 (RaptorQ Forward Error Correction).

  They were produced with `SourceBlockEncoder::new` using `sub_blocks = 1` and
  `symbol_alignment = 1`, which disables symbol interleaving and matches this
  Elixir library's single-source-block model exactly. For each case the harness
  emitted:

   * the `K` source symbols (encoding symbol IDs 0..K-1), and
   * the first 8 repair symbols, whose RFC 6330 encoding-symbol IDs are
     K'..K'+7 (i.e. `repair_packets(0, 8)`).

  Only the hardcoded outputs are committed below; no Rust or Python tooling is
  required to run this test.

  ## Status: CONFORMANT

  All three cases below pass: the source-symbol split, the 8 repair
  symbols (RFC IDs K'..K'+7), and full data recovery via
  `Raptorq.decode/3` all match the cberner 2.0.1 reference output.

  Run with:

      mix test --only conformance

  Recovery requires K' symbols (the extended source-block size), not K.
  The zero-padding source symbols (ISIs K..K'-1) are regenerated from C
  and supplied so step 2 holds even for extended blocks (e.g. K=16, K'=18).
  """

  use ExUnit.Case, async: true

  @moduletag :conformance

  defp bin(hex), do: Base.decode16!(hex, case: :lower)

  defp assert_case(data, k, source_hex, repair_hex) do
    {:ok, %{c: c, params: params, k_prime: kp, source_symbols: src}} = Raptorq.encode(data, k)

    # 1. Our source-symbol split must match the reference exactly.
    assert src == Enum.map(source_hex, &bin/1)

    # 2. Decoding the source symbols must recover the data.
    #
    #    Recovery always needs K' symbols to solve for the intermediate C, even
    #    when K < K'. The K..K'-1 padding symbols are all-zero by construction,
    #    so they are regenerated from C and appended here (when K < K').
    source_full =
      if kp > k do
        src ++ Enum.map(k..(kp - 1), fn isi -> Raptorq.repair(c, params, isi) end)
      else
        src
      end

    received_source = Enum.with_index(source_full) |> Enum.map(fn {s, i} -> {i, s} end)
    {:ok, recovered} = Raptorq.decode(received_source, k)
    assert recovered == data

    # 3. Our repair symbols (RFC IDs K'..K'+7) must match the reference.
    Enum.with_index(repair_hex)
    |> Enum.each(fn {h, i} ->
      assert Raptorq.repair(c, params, kp + i) == bin(h), "repair offset #{i}"
    end)

    # 4. Decoding source + repair symbols (proper RFC IDs) also recovers data.
    received_all =
      Enum.map(received_source, fn {i, s} -> {i, s} end) ++
        Enum.map(Enum.with_index(repair_hex), fn {h, i} -> {kp + i, bin(h)} end)

    {:ok, recovered2} = Raptorq.decode(received_all, k)
    assert recovered2 == data
  end

  test "case A: 80 bytes, symbol_size 8, K=10" do
    data = for i <- 0..79, into: <<>>, do: <<i>>

    source = [
      "0001020304050607",
      "08090a0b0c0d0e0f",
      "1011121314151617",
      "18191a1b1c1d1e1f",
      "2021222324252627",
      "28292a2b2c2d2e2f",
      "3031323334353637",
      "38393a3b3c3d3e3f",
      "4041424344454647",
      "48494a4b4c4d4e4f"
    ]

    repairs = [
      "26a53dbe10930b88",
      "54afbf449f64748f",
      "5216da9e5f1bd793",
      "0f7be793c2b62a5e",
      "f0dfae814c63123d",
      "7eacc71511c3a87a",
      "b010ed4d0aaa57f7",
      "93d1175586c40240"
    ]

    assert_case(data, 10, source, repairs)
  end

  test "case B: 200 bytes, symbol_size 10, K=20" do
    data = for i <- 0..199, into: <<>>, do: <<i>>

    source = [
      "00010203040506070809",
      "0a0b0c0d0e0f10111213",
      "1415161718191a1b1c1d",
      "1e1f2021222324252627",
      "28292a2b2c2d2e2f3031",
      "32333435363738393a3b",
      "3c3d3e3f404142434445",
      "464748494a4b4c4d4e4f",
      "50515253545556575859",
      "5a5b5c5d5e5f60616263",
      "6465666768696a6b6c6d",
      "6e6f7071727374757677",
      "78797a7b7c7d7e7f8081",
      "82838485868788898a8b",
      "8c8d8e8f909192939495",
      "969798999a9b9c9d9e9f",
      "a0a1a2a3a4a5a6a7a8a9",
      "aaabacadaeafb0b1b2b3",
      "b4b5b6b7b8b9babbbcbd",
      "bebfc0c1c2c3c4c5c6c7"
    ]

    repairs = [
      "fdf81c198a8ff0f5b4b1",
      "3f9179d7a9077ed0b21c",
      "d93da94d3dd9997d6286",
      "a3d325553d4dfe8e4a3a",
      "54bb48a7ee015cb309e6",
      "4f73576b4975f0cc2e12",
      "781d06637613096cb2d7",
      "1b64720dd8a7453ae59a"
    ]

    assert_case(data, 20, source, repairs)
  end

  test "case C: 256 bytes, symbol_size 16, K=16" do
    data = for i <- 0..255, into: <<>>, do: <<i>>

    source = [
      "000102030405060708090a0b0c0d0e0f",
      "101112131415161718191a1b1c1d1e1f",
      "202122232425262728292a2b2c2d2e2f",
      "303132333435363738393a3b3c3d3e3f",
      "404142434445464748494a4b4c4d4e4f",
      "505152535455565758595a5b5c5d5e5f",
      "606162636465666768696a6b6c6d6e6f",
      "707172737475767778797a7b7c7d7e7f",
      "808182838485868788898a8b8c8d8e8f",
      "909192939495969798999a9b9c9d9e9f",
      "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf",
      "b0b1b2b3b4b5b6b7b8b9babbbcbdbebf",
      "c0c1c2c3c4c5c6c7c8c9cacbcccdcecf",
      "d0d1d2d3d4d5d6d7d8d9dadbdcdddedf",
      "e0e1e2e3e4e5e6e7e8e9eaebecedeeef",
      "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
    ]

    repairs = [
      "912ef24d57e8348b00bf63dcc679a51a",
      "6ed701b8b009df66cf76a01911a87ec7",
      "660bbcd1cfa215782944f39e80ed5a37",
      "a590cffa71441b2e10257a4fc4f1ae9b",
      "ba55799621cee20d917e52bd0ae5c926",
      "6ed10db2a817cb74ff409c2339865ae5",
      "7a93b55cf91036df6188ae47e20b2dc4",
      "9ed30449b7fa2d60cc81561be5a87f32"
    ]

    assert_case(data, 16, source, repairs)
  end
end
