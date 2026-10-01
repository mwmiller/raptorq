# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-09-30

### Fixed

- **Silent data corruption in `Raptorq.decode/3`.** Phase-1 row selection
  in the 5-phase solver picked rows by total non-zero count instead of by
  their non-zero V entries as required by RFC 6330 §5.4.2.2. A row with
  more V entries than the minimum `r` could be chosen, leaving stray V
  entries in the I block, breaking its diagonal, and corrupting the solve
  (roughly 5–10% of random symbol subsets returned wrong data). Selection
  now follows the RFC. As defense in depth, every candidate solution is
  also verified against the full constraint system — the LDPC/HDPC rows as
  well as the rows for the received symbols — before any data is returned;
  unverifiable solutions return `{:error, :singular}` instead of corrupt
  data. When extra symbols are available, candidate subsets are tried as
  sliding windows (bounded attempts, including the symbols in reverse
  order) so decoding recovers from a bad leading subset.
- The solver no longer raises `ArgumentError` (`Division by zero`) when it
  encounters a missing or zero pivot in the I block; that state is reported
  as `{:error, :singular}`.
- Constraint rows may contain explicit zero entries from GF(2^8)
  cancellations; these are stripped before solving because stored zeros
  violate the solver's sparse invariants.
- The solver now always returns `{:error, :singular}`. Previously the
  phase-2 dense elimination returned `{:error, {:singular, col}}`, which
  `Raptorq.StreamingDecoder` did not recognize and surfaced as a hard
  error instead of `:incomplete`.
- `Raptorq.encode/2` and `Raptorq.encode/3` propagate `{:error, reason}`
  instead of raising `MatchError` when the solver fails, and verify the
  intermediate symbols against every constraint row before returning.
- `Raptorq.decode/3` counts symbols after deduplication, so duplicate ISIs
  no longer inflate the symbol count toward the `:insufficient_symbols`
  threshold.
- `Raptorq.StreamingDecoder` no longer re-runs the solver for every symbol
  received after a successful decode; the decoded result is cached.

### Added

- Input validation with clear `ArgumentError` messages across the API:
  `k` must be a positive integer within the SIOP table, `isi` must be a
  non-negative integer, `symbol_size` a positive integer, `data_size` a
  non-negative integer, `received` a well-formed list of `{isi, symbol}`
  tuples, and symbols must be non-empty binaries.
- `Raptorq.encode/3` raises `ArgumentError` when data exceeds
  `k * symbol_size` instead of silently truncating it.
- Typespecs (`@type`/`@spec`) across the public and internal API.
- Static analysis via `dialyxir` (`mix dialyzer`), clean as of this release.
- GitHub Actions CI: formatting, Credo strict, `--warnings-as-errors`,
  tests with 90% coverage gate, docs build, and Dialyzer across
  Elixir 1.18–1.20.

### Changed

- RFC-compliant phase-1 row selection (see Fixed) also picks much sparser
  pivots: decoding is roughly 8-20x faster for larger blocks (K=400:
  ~0.42 s instead of ~8.7 s on the same machine). README benchmarks updated.
- Removed the unused `Raptorq.Precoding` module (dead code, no callers),
  along with the unused `run_phases/3` solver helper.
- `Raptorq.StreamingDecoder` struct gained `symbol_size` and `decoded`
  fields; `add_symbol/3` validates its arguments.
- Corrected stale usage rules in `AGENTS.md` (e.g. `symbol_size = 1` is
  supported by this implementation; the `>= 2` limit is a cberner interop
  constraint only).

## [0.2.0] - 2026-07-11

### Added

- `Raptorq.StreamingDecoder` for ergonomically ingesting symbols one by one and automatically decoding when sufficient symbols are collected.
- `Raptorq.encode/3` to support automatic zero-padding and chunking of source payloads that are not perfectly divisible by the symbol size.

### Changed

- `Raptorq.encode/2` now strictly enforces that the source data length is an exact multiple of `k` (to prevent hidden padding bugs). For automatic padding, use `encode/3`.
- Replaced the README performance estimates with accurate, real-world `:timer.tc` benchmarks for the pure Elixir 5-phase sparse solver.

## [0.1.0] - 2025-05-16

### Added

- Initial release of the RaptorQ codec (RFC 6330).
- `Raptorq.encode/2` to compute intermediate symbols for a block of `K` source symbols.
- `Raptorq.repair/3` to generate encoding symbols for arbitrary ISIs.
- `Raptorq.decode/3` to recover source data from any `K'` distinct symbols.
- Dense reference solver (`Raptorq.Solver`) and O(L²) 5-phase sparse solver (`Raptorq.Solver5`).
- Precomputed tables in `priv/` (SIOP, Deg, OCT_LOG/EXP, V0–V3).
