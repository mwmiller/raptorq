defmodule Raptorq do
  @moduledoc """
  RaptorQ forward error correction (RFC 6330).

  ## Encoding

      data = File.read!("myfile.dat")
      {:ok, %{c: c_syms, params: params, symbol_size: sym_size}} = Raptorq.encode(data, 10)

      # Generate repair symbols for any ISI
      repair = Raptorq.repair(c_syms, params, sym_size, 100_000)

  ## Decoding (coming soon)

      received = [{0, sym_0}, {1, sym_1}, ..., {100_000, repair_100_000}]
      {:ok, data} = Raptorq.decode(received, 10, sym_size, data_size)
  """

  alias Raptorq.{ConstraintMatrix, Solver, Encoder, Decoder, SIOP}

  @doc """
  Encode source data for block of K source symbols.

  `data` is the source data as a binary.  `k` is the number of source
  symbols in the block.

  Returns `{:ok, %{c: intermediate_symbols, params: siop_params,
  symbol_size: sym_size, k_prime: kp, source_symbols: source_syms}}`.
  """
  def encode(data, k) do
    sym_size = ceil(byte_size(data) / k)
    source_syms = split_symbols(data, k, sym_size)

    kp = SIOP.values_for(k, :close).k
    {:ok, c_syms, params} = compute_intermediate(source_syms, k, kp, sym_size)

    {:ok, %{c: c_syms, params: params, symbol_size: sym_size, k_prime: kp,
            source_symbols: source_syms}}
  end

  @doc """
  Generate one repair symbol for the given ISI.

  `c_syms` is the list of L intermediate symbols.
  `params` is the SIOP parameter map.
  `sym_size` is the symbol size in bytes.
  `isi` is the encoding symbol ID (must be >= K' for repair symbols).

  Returns the repair symbol as a binary.
  """
  def repair(c_syms, params, _sym_size, isi) do
    Encoder.encode_symbol(c_syms, params, isi)
  end

  @doc """
  Decode received symbols to recover original source data.

  `received` is a list of `{isi, symbol_binary}` tuples.
  `k` is the number of source symbols in the original block.
  `data_size` (optional) truncates output to the original data size.
  """
  def decode(received, k, data_size \\ nil) do
    Decoder.decode(received, k, data_size)
  end

  # ── Internal helpers ──────────────────────────────────────────────────

  defp split_symbols(data, k, sym_size) do
    for i <- 0..(k - 1) do
      offset = i * sym_size
      part = binary_part(data, offset, min(sym_size, byte_size(data) - offset))
      pad_to(part, sym_size)
    end
  end

  defp pad_to(bin, size) when byte_size(bin) == size, do: bin
  defp pad_to(bin, size), do: bin <> <<0::unit(8)-size(size - byte_size(bin))>>

  defp compute_intermediate(source_syms, k, kp, sym_size) do
    %{s: s, h: h} = SIOP.values_for(kp, :exact)

    zero = :binary.copy(<<0>>, sym_size)

    # Build D vector: S+H zero symbols + K' source symbols (with K'-K zero padding)
    padded_syms = source_syms ++ List.duplicate(zero, kp - k)

    d_syms = List.duplicate(zero, s + h) ++ padded_syms

    # Build constraint matrix
    {constraint_rows, params} = ConstraintMatrix.build(kp)

    # Solve A*C = D
    case Solver.solve(constraint_rows, params, d_syms) do
      {:ok, c_syms} -> {:ok, c_syms, params}
      {:error, reason} -> {:error, reason}
    end
  end
end
