# RaptorQ

RaptorQ forward error correction (RFC 6330) for Elixir — a fountain code
that lets a receiver recover original source data from any K' of a virtually
unlimited stream of encoded symbols.

## Installation

```elixir
def deps do
  [
    {:raptorq, "~> 0.2.0"}
  ]
end
```

## Quick Start

```elixir
# 1. Encode source data for a block of K source symbols.
# We use `encode/3` to automatically pad the data to a valid symbol size.
data = File.read!("myfile.dat")
k = 10
sym_size = ceil(byte_size(data) / k)
{:ok, state} = Raptorq.encode(data, k, sym_size)

c = Map.get(state, :c)
params = Map.get(state, :params)

# 2. Generate repair symbols for any ISI (≥ K')
repair_1 = Raptorq.repair(c, params, 100_000)
repair_2 = Raptorq.repair(c, params, 100_001)

# 3. Decode from any K' distinct ISIs
# The StreamingDecoder is recommended for network streams.
decoder = Raptorq.StreamingDecoder.new(k, byte_size(data))

{:ok, :incomplete, decoder} = Raptorq.StreamingDecoder.add_symbol(decoder, 0, sym_0)
# ... accumulate more symbols ...
{:ok, {:decoded, recovered_data}, _decoder} = Raptorq.StreamingDecoder.add_symbol(decoder, 100_000, repair_1)
```

## Streaming Decoder vs. Batch Decoding

When receiving data over a network or radio link, symbols arrive asynchronously. The `Raptorq.StreamingDecoder` provides a stateful, ergonomic way to ingest symbols one by one and automatically attempts to solve the constraint matrix once enough symbols are available.

For offline or batch usage, you can pass a complete list of accumulated tuples directly to `Raptorq.decode/3`:

```elixir
# Accumulated over multiple beacon receptions
received = [{57, sym_57}, {3, sym_3}, {100_000, repair_1}, ...]

# The original payload size must be known to strip trailing padding.
{:ok, recovered_data} = Raptorq.decode(received, k, byte_size(payload))
```

## Radio Beacon Usage

A radio beacon is a one-way transmitter that periodically broadcasts repair
symbols. Receivers tune in at any time — they just need any K' distinct
symbols to recover the full message.

### Beacon Side

```elixir
# Payload can be any size; Raptorq splits it into K equal symbols.
# encode/3 handles necessary zero-padding for non-aligned lengths.
payload = File.read!("telemetry.bin")
k = 10
sym_size = ceil(byte_size(payload) / k)
{:ok, state} = Raptorq.encode(payload, k, sym_size)

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
# Initialize decoder with the expected K and payload size (negotiated via protocol)
decoder = Raptorq.StreamingDecoder.new(k, expected_payload_size)

def handle_incoming_symbol(decoder, isi, sym) do
  case Raptorq.StreamingDecoder.add_symbol(decoder, isi, sym) do
    {:ok, {:decoded, data}, _decoder} ->
      IO.puts("Successfully recovered payload!")
      handle_data(data)
    
    {:ok, :incomplete, new_decoder} ->
      # Save state and wait for the next symbol
      save_state(new_decoder)
      
    {:error, reason, _decoder} ->
      IO.inspect(reason, label: "Decode Error")
  end
end
```

### Handling Large Payloads

For large payloads (megabytes+), increase `K` to keep individual symbol sizes
manageable. The decoder needs at least K' distinct ISIs, so higher K means
collecting more symbols before decoding succeeds.

```elixir
# Large payload: K = 500, each symbol ≈ payload_size / 500 bytes
payload = File.read!("large_satellite_image.tiff")
k = 500
sym_size = ceil(byte_size(payload) / k)
{:ok, state} = Raptorq.encode(payload, k, sym_size)

# K' is computed from the SIOP table (≈ 511 for K=500)
kp = Map.get(state, :k_prime)
# Receiver must collect at least kp distinct symbols
```

The beacon and receiver must agree on `k` (source symbols) and on the original
payload size (so the receiver can strip padding). The ISIs are the **ESI** (Encoding Symbol ID) from RFC 6330 — any
non-negative integer up to 2²⁰−1 works, giving over a million unique encoded
symbols per block. No return channel needed.

## Performance

The following benchmarks measure the raw decoding/solver time (`Raptorq.decode/3`) using Elixir's `:timer.tc` on a single process. Since the 5-phase sparse solver runs in pure Elixir, time scales quadratically with $L$ (which is proportional to $K$). 

*Run on a single core; to reproduce, you can generate an array of received symbols (e.g. `needed = L - S - H`) and pass them to the decoder.*

| Block Size | L | 5-Phase Sparse Solver |
|------------|---|-----------------------|
| K=10   | 27  | ~2.0 ms |
| K=50   | 78  | ~36 ms |
| K=100  | 128 | ~160 ms |
| K=200  | 233 | ~1.0 s |
| K=300  | 340 | ~3.5 s |
| K=400  | 452 | ~8.7 s |
