# Usage rules for the raptorq package
%{
  rules: [
    %{
      id: "raptorq-encode-symbol-size",
      title: "Encode requires data length multiple of k",
      description: """
      `Raptorq.encode/2` requires `byte_size(data)` to be an exact multiple of `k`
      and at least `k` bytes (one byte per source symbol). It does **not** pad.
      Use `Raptorq.encode/3` for automatic padding to `k * symbol_size`.

      `Raptorq.encode/3` raises `ArgumentError` when the data is larger than
      `k * symbol_size` — it never silently truncates. Increase `k` or
      `symbol_size` to fit the data.

      Example (correct):
      ```elixir
      data = :crypto.strong_rand_bytes(40)  # multiple of k: 10
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
      title: "symbol_size must be a positive integer",
      description: """
      `symbol_size` must be a positive integer (`>= 1`); `symbol_size = 1`
      works correctly in this (pure Elixir) implementation.

      The stricter `symbol_size >= 2` requirement applies only when
      interoperating with the cberner/raptorq Rust implementation
      (see the interop rule below).
      """,
      severity: :error,
      tags: [:api, :precondition]
    },
    %{
      id: "raptorq-repair-isi-semantics",
      title: "repair/3 ISI is K' + offset, not raw index",
      description: """
      `Raptorq.repair(c, params, isi)` expects the **Intermediate Symbol Identifier (isi)**
      and returns the symbol binary directly (no `{:ok, ...}` wrapper).
      `isi` must be a non-negative integer.

      For repair symbols, ISI = `K' + offset` where `K' = params.k`.

      cberner's `repair_packets(start, n)` uses `ISI = K' + start`.
      So `repair_packets(0, 8)` yields ISIs `K'..K'+7`.

      Correct usage:
      ```elixir
      # First repair symbol (ISI = K')
      sym = Raptorq.repair(c, params, params.k)

      # Next 7 repair symbols
      for isi <- params.k..(params.k + 6), do: Raptorq.repair(c, params, isi)
      ```
      """,
      severity: :warning,
      tags: [:api, :repair, :isi]
    },
    %{
      id: "raptorq-encode-returns-intermediate",
      title: "encode/2 and encode/3 return intermediate symbols C[i], not source symbols",
      description: """
      `Raptorq.encode/2` and `Raptorq.encode/3` return a map with key `:c`
      containing **intermediate symbols** `C[0..K'-1]`. These are NOT the
      original source symbols.

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

      Malformed input raises `ArgumentError`: `received` must be a list of
      `{isi, symbol}` tuples (non-negative integer ISI, non-empty binary symbol),
      `k` must be a positive integer, and `data_size` (when given) a
      non-negative integer.
      """,
      severity: :error,
      tags: [:api, :decode, :precondition]
    },
    %{
      id: "raptorq-decode-verified",
      title: "decode/3 verifies every solution before returning data",
      description: """
      Every candidate solution from `Raptorq.decode/3` is verified against
      the full constraint system — the LDPC/HDPC rows as well as the rows
      for the received symbols. A successful `{:ok, data}` is therefore
      always consistent with the received symbols; failed verifications
      surface as `{:error, :singular}` rather than corrupt data.

      When more than K' symbols are available, the decoder tries sliding
      window subsets (bounded attempts), so extra symbols improve the
      chance of recovery.

      `Raptorq.StreamingDecoder` treats `{:error, :singular}` as
      `:incomplete` and keeps accumulating.
      """,
      severity: :info,
      tags: [:api, :decode, :correctness]
    },
    %{
      id: "raptorq-k-prime-vs-k",
      title: "Distinguish K (source symbols) from K' (intermediate symbols)",
      description: """
      - `params.k` = K' = extended source block (intermediate) symbol count
      - `params.l` = `params.k + params.s + params.h` = constraint matrix size L
      - The decoder needs `params.l - params.s - params.h` = `params.k` = K' distinct symbols
      - K is the **user-supplied** `k` argument to `encode`/`decode`/`StreamingDecoder.new`
        (K <= K'); it is not derivable from the params as `params.k - params.s - params.h`
      - Source symbols are ISI `0..K-1`; repair symbols start at ISI `K'`
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
      - symbol_size >= 2 (cberner constraint; this library itself allows 1)
      - ISI space shared: source 0..K-1, repair K'..infinity

      Reference interop vectors in `test/fixtures/cberner_interop_vectors.txt`
      and `test/raptorq_interop_test.exs`.
      """,
      severity: :info,
      tags: [:interop, :conformance]
    }
  ]
}