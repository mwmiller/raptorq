defmodule RaptorqInteropTest do
  @moduledoc """
  Interoperability regression test against the de-facto RFC 6330 reference
  implementation, `raptorq` 2.0.1 by Christopher Berner
  (https://github.com/cberner/raptorq).

  ## Where the vectors come from

  The reference vectors in `test/fixtures/cberner_interop_vectors.txt` were
  produced by a small Rust harness (`/tmp/rq_probe`) that drives
  `SourceBlockEncoder::new` with `sub_blocks = 1` and `symbol_alignment = 1`
  — this disables symbol interleaving and matches this library's single
  source-block model exactly.  For each case the harness emits:

    * the `K` source symbols (encoding-symbol IDs 0..K-1),
    * the first 8 repair symbols (`repair_packets(0, 8)` → IDs K'..K'+7),
    * three batches of 8 repair symbols at *extreme* IDs
      (`repair_packets(1000, 8)`, `repair_packets(50000, 8)`,
       `repair_packets(100000, 8)`).

  `repair_packets(start, n)` in cberner returns IDs `start + K' .. start + K' + n - 1`,
  so the extreme batches land at `K'+1000`, `K'+50000`, `K'+100000` etc.

  ## Why these cases matter

  The cases probe behaviour the happy-path conformance vectors do not:

    * **counter / zero / 0xFF payloads** — exercise every octet value and the
      all-zero / all-one corner cases.
    * **odd symbol sizes** (7, 13) — non-power-of-two symbol sizes.
    * **K = 1** (case F) and **K < K'** (K=15,16,30) — minimal blocks and
      blocks that require K'-K zero-padding of the source.
    * **extreme repair IDs** — anything ≥ K' is a genuine repair symbol and is a
      linear combination of *all* L intermediate symbols. A C vector that is
      under-determined (e.g. produced by a singular constraint matrix) will
      reproduce the source and the first few repairs yet diverge on any
      independent repair. Checking IDs up to 100000 forces that the full
      intermediate-symbol solution is the unique, correct one.

  Re-run the harness and overwrite the fixture if the RFC parameters change.
  """

  use ExUnit.Case

  @fixture "test/fixtures/cberner_interop_vectors.txt"

  # ── Parsing of the reference fixture ──────────────────────────────────────

  defp parse_case_header(rest) do
    [tag, sym, k, pat, len] =
      rest
      |> String.split(" ")
      |> Enum.map(fn s ->
        [_, v] = String.split(s, "=", parts: 2)
        v
      end)

    %{
      tag: tag,
      sym: String.to_integer(sym),
      k: String.to_integer(k),
      pat: pat,
      len: String.to_integer(len),
      src: Map.new(),
      rep: Map.new(),
      rhi: Map.new()
    }
  end

  defp update_rhi(c, hi, i, h) do
    rhi = Map.update(c.rhi, hi, Map.new(), fn m -> Map.put(m, i, h) end)
    Map.put(c, :rhi, rhi)
  end

  defp parse(lines) do
    Enum.reduce(lines, [], fn line, acc ->
      case line do
        "CASE " <> rest ->
          c = parse_case_header(rest)
          [c | acc]

        "S " <> rest ->
          [c | restc] = acc
          [i, h] = String.split(rest, " ")
          [Map.put(c, :src, Map.put(c.src, String.to_integer(i), h)) | restc]

        "R " <> rest ->
          [c | restc] = acc
          [i, h] = String.split(rest, " ")
          [Map.put(c, :rep, Map.put(c.rep, String.to_integer(i), h)) | restc]

        "RH" <> rest ->
          [c | restc] = acc
          [hi, i, h] = String.split(rest, " ")
          [update_rhi(c, String.to_integer(hi), String.to_integer(i), h) | restc]

        "" ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  # Rebuild the original source payload from the recorded pattern.
  defp gen_payload(pat, len) do
    for i <- 0..(len - 1), into: <<>> do
      case pat do
        "ctr" -> <<rem(i, 256)>>
        "zero" -> <<0>>
        "ff" -> <<255>>
      end
    end
  end

  defp assert_hex(label, got_bin, want_hex) do
    got = Base.encode16(got_bin, case: :lower)

    if got != want_hex do
      flunk("#{label}: expected #{want_hex}, got #{got}")
    end
  end

  defp cases do
    File.read!(@fixture) |> String.split("\n") |> parse()
  end

  # ── Source-symbol split ───────────────────────────────────────────────────

  describe "source-symbol split (encoding-symbol IDs 0..K-1)" do
    test "matches cberner source packets" do
      for c <- cases() do
        %{tag: tag, pat: pat, len: len, sym: sym, src: src} = c
        data = gen_payload(pat, len)
        {:ok, %{source_symbols: src_syms}} = Raptorq.encode(data, div(len, sym))

        for {i, want} <- src do
          assert_hex("case #{tag} S#{i}", Enum.at(src_syms, i, ""), want)
        end
      end
    end
  end

  # ── Repair symbols at low ISI (K'..K'+7) ────────────────────────────────

  describe "repair symbols at low ISI (K'..K'+7)" do
    test "match cberner repair_packets(0, 8)" do
      for c <- cases() do
        %{tag: tag, pat: pat, len: len, sym: sym, rep: rep} = c
        data = gen_payload(pat, len)
        {:ok, %{c: c_syms, params: params, k_prime: kp}} = Raptorq.encode(data, div(len, sym))

        for {i, want} <- rep do
          got = Raptorq.repair(c_syms, params, kp + i)
          assert_hex("case #{tag} R#{i}", got, want)
        end
      end
    end
  end

  # ── Repair symbols at extreme ISI ────────────────────────────────────────

  describe "repair symbols at extreme ISI (K'+1000, K'+50000, K'+100000)" do
    test "match cberner repair_packets(1000|50000|100000, 8)" do
      for c <- cases() do
        %{tag: tag, pat: pat, len: len, sym: sym, rhi: rhi} = c
        data = gen_payload(pat, len)
        {:ok, %{c: c_syms, params: params, k_prime: kp}} = Raptorq.encode(data, div(len, sym))

        for {hi, m} <- rhi do
          for {i, want} <- m do
            got = Raptorq.repair(c_syms, params, hi + kp + i)
            assert_hex("case #{tag} RH#{hi}/#{i}", got, want)
          end
        end
      end
    end
  end
end
