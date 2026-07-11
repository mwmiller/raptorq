# RaptorQ

RaptorQ forward error correction (RFC 6330) for Elixir — a fountain code
that lets a receiver recover original source data from any K' of a virtually
unlimited stream of encoded symbols.

## Installation

```elixir
def deps do
  [
    {:raptorq, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Encode source data for a block of K source symbols
data = File.read!("myfile.dat")
{:ok, state} = Raptorq.encode(data, 10)

c = Map.get(state, :c)
params = Map.get(state, :params)

# Generate repair symbols for any ISI (≥ K')
repair_1 = Raptorq.repair(c, params, 100_000)
repair_2 = Raptorq.repair(c, params, 100_001)

# Decode from any K' distinct ISIs
received = [{0, sym_0}, {3, sym_3}, {100_000, repair_1} | more ...]
{:ok, data} = Raptorq.decode(received, 10, byte_size(data))

# `decode/3` needs at least K' (not K) distinct symbols; K' ≥ K comes from
# the SIOP table. Passing the original `byte_size(data)` strips any padding.
```

## Radio Beacon Usage

A radio beacon is a one-way transmitter that periodically broadcasts repair
symbols. Receivers tune in at any time — they just need any K' distinct
symbols to recover the full message.

### Beacon Side

```elixir
# Payload can be any size; Raptorq splits it into K equal symbols
payload = File.read!("telemetry.bin")
k = 10
{:ok, state} = Raptorq.encode(payload, k)
c = Map.get(state, :c)
params = Map.get(state, :params)

# Transmit one repair symbol per broadcast slot
isi = read_nonce_from_rtc()
repair_sym = Raptorq.repair(c, params, isi)
transmit(isi, repair_sym)
write_nonce(isi + 1)
```

### Receiver Side

```elixir
# Accumulated over multiple beacon receptions
received = [{57, sym_57}, {3, sym_3}, {92, sym_92}, {14, sym_14}, ...]

# Decode once K' distinct symbols collected. The original payload size must
# be known (here via the protocol) so padding can be stripped.
{:ok, data} = Raptorq.decode(received, k, byte_size(payload))
```

### Handling Large Payloads

For large payloads (megabytes+), increase `K` to keep individual symbol sizes
manageable. The decoder needs at least K' distinct ISIs, so higher K means
collecting more symbols before decoding succeeds.

```elixir
# Large payload: K = 500, each symbol ≈ payload_size / 500 bytes
payload = File.read!("large_satellite_image.tiff")
k = 500
{:ok, state} = Raptorq.encode(payload, k)

# K' is computed from the SIOP table (≈ 511 for K=500)
kp = Map.get(state, :k_prime)
# Receiver must collect at least kp distinct symbols
```

The beacon and receiver must agree on `k` (source symbols) and on the original
payload size (so the receiver can pass `data_size` to `decode/3` and strip
padding). The ISIs are the **ESI** (Encoding Symbol ID) from RFC 6330 — any
non-negative integer up to 2²⁰−1 works, giving over a million unique encoded
symbols per block. No return channel needed.

## Performance

| Block Size | 5-Phase Sparse Solver |
|------------|-----------------------|
| K=10   L=27 | ~1 ms |
| K=200  L=233 | ~320 ms |
| K=500  L=558 | ~3.7 s |
| K=1000 L=1071 | ~23 s |

Uses the 5-phase sparse solver (`Raptorq.Solver`) for efficient O(L²) decoding
of intermediate symbols. The previous `Solver5` (dense) implementation was removed.

## Tests

```bash
mix test
```

## Pre-commit Checks

```bash
mix precommit
```

Runs format check, Credo strict, and compilation with warnings-as-errors.
