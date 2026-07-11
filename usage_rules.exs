# Usage rules for the raptorq package
%{
  rules: [
    %{
      id: "raptorq-encode-symbol-size",
      title: "Encode requires data length multiple of symbol_size",
      description: """
      `Raptorq.encode/2` requires the input data length to be an exact multiple of
      `symbol_size`. It does **not** pad internally. Callers must pad/truncate before
      encoding or use the higher-level `Raptorq.encode/3` which handles chunking.

      Example (correct):
      ```elixir
      data = :crypto.strong_rand_bytes(40)  # multiple of symbol_size: 10
      {:ok, state} = Raptorq.encode(data, 10)
      ```

      Will raise:
      ```elixir
      data = "not-a-multiple"
      Raptorq.encode(data, 10)  # ArgumentError
      ```
      """,
      severity: :error,
      tags: [:api, :encode, :precondition]
    },
    %{
      id: "raptorq-symbol-size-one",
      title: "symbol_size = 1 is unsupported",
      description: """
      The underlying cberner/raptorq Rust implementation panics on `symbol_size == 1`.
      This library propagates that constraint: `symbol_size` must be >= 2.
      """,
      severity: :error,
      tags: [:api, :precondition]
    },
    %{
      id: "raptorq-repair-isi-semantics",
      title: "repair/3 ISI is K' + offset, not raw index",
      description: """
      `Raptorq.repair(c, params, isi)` expects the **Intermediate Symbol Identifier (ISI)**.
      For repair symbols, ISI = `K' + offset` where `K' = params.k` (number of source symbols).

      cberner's `repair_packets(start, n)` uses `ISI = K' + start`.
      So `repair_packets(0, 8)` yields ISIs `K'..K'+7`.

      Correct usage:
      ```elixir
      # First repair symbol (ISI = K')
      {:ok, sym} = Raptorq.repair(c, params, params.k)

      # Next 7 repair symbols
      for isi <- params.k..(params.k + 6), do: Raptorq.repair(c, params, isi)
      ```
      """,
      severity: :warning,
      tags: [:api, :repair, :isi]
    },
    %{
      id: "raptorq-encode-returns-intermediate",
      title: "encode/2 returns intermediate symbols C[i], not source symbols",
      description: """
      `Raptorq.encode/2` returns a map with key `:c` containing **intermediate symbols**
      `C[0..K'-1]`. These are NOT the original source symbols.

      To get source symbols (ISI 0..K-1):
      - Use `state.source_symbols` (pre-computed source block)
      - Or call `Raptorq.repair(c, params, isi)` for `isi in 0..K-1`
      """,
      severity: :warning,
      tags: [:api, :encode, :intermediate-symbols]
    },
    %{
      id: "raptorq-decode-requires-exact-symbol-size",
      title: "decode/3 requires all received symbols to have identical size",
      description: """
      `Raptorq.decode/3` validates that every received symbol tuple `{isi, binary}`
      has the same `byte_size`. Mixed sizes return `{:error, :inconsistent_symbol_size}`.
      """,
      severity: :error,
      tags: [:api, :decode, :precondition]
    },
    %{
      id: "raptorq-k-prime-vs-k",
      title: "Distinguish K (source symbols) from K' (intermediate symbols)",
      description: """
      - `params.k` = K' = number of intermediate symbols (includes LDPC/HDPC padding)
      - `params.k - params.s - params.h` = K = original source symbols
      - Source symbols are ISI 0..K-1; repair symbols start at ISI K'
      - cberner Rust API uses K' internally; this library exposes both via params
      """,
      severity: :info,
      tags: [:concept, :parameters]
    },
    %{
      id: "raptorq-interop-cberner",
      title: "Interop with cberner/raptorq 2.x",
      description: """
      Verified conformant with cberner/raptorq 2.0.1 (Rust) under:
      - sub_blocks = 1, symbol_alignment = 1
      - data length exact multiple of symbol_size
      - symbol_size >= 2
      - ISI space shared: source 0..K-1, repair K'..infinity

      Reference interop vectors in `test/fixtures/cberner_interop_vectors.txt`
      and `test/raptorq_interop_test.exs`.
      """,
      severity: :info,
      tags: [:interop, :conformance]
    }
  ]
}