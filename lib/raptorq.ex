defmodule Raptorq do
  @moduledoc """
  RaptorQ forward error correction (RFC 6330).

  ## Quick start

      # Encode: chunk data into K symbols of size `sym_size` (pads if necessary)
      data = File.read!("myfile.dat")
      k = 10
      sym_size = ceil(byte_size(data) / k)
      {:ok, state} = Raptorq.encode(data, k, sym_size)

      # Generate repair symbols for any ISI ≥ K'
      c = Map.get(state, :c)
      p = Map.get(state, :params)
      repair_1 = Raptorq.repair(c, p, 100_000)

      # Decode: recover data gracefully using the StreamingDecoder
      decoder = Raptorq.StreamingDecoder.new(k, byte_size(data))
      {:ok, :incomplete, decoder} = Raptorq.StreamingDecoder.add_symbol(decoder, 0, sym_0)
      # ... receive more symbols ...
      {:ok, {:decoded, data}, _decoder} = Raptorq.StreamingDecoder.add_symbol(decoder, 100_000, repair_1)

  ## Architecture

  The source data is split into K equal-sized symbols.  Using the
  SIOP table, K' ≥ K is chosen, and the K'-K tail symbols are zero-
  padded.  The constraint matrix A (L = S+H+K' rows/columns) is built
  linking intermediate symbols C to the source symbols via A·C = D.

  Encoding symbols for any ISI (0 … 2²⁰−1) are linear combinations of
  C produced by Tuple[K', ISI] (RFC 6330 §5.3.5.4).  The receiver
  builds a system from LDPC+HDPC rows (always D=0) and G_ENC rows for
  received ISIs, then solves for C to recover the source data.

  ## Performance

  Uses the 5-phase sparse solver (`Raptorq.Solver`) for efficient
  O(L²) decoding of the intermediate symbols C.
  """

  alias Raptorq.{ConstraintMatrix, Decoder, Encoder, SIOP, Solver, Validation}

  @typedoc "An encoding symbol identifier (source symbols `0..K-1`, repair symbols `≥ K'`)."
  @type isi :: non_neg_integer()

  @typedoc "SIOP pre-coding parameters (RFC 6330 §5.3.3.3)."
  @type siop_params :: %{
          k: pos_integer(),
          j: integer(),
          s: integer(),
          h: integer(),
          w: integer(),
          l: integer(),
          p: integer(),
          p1: integer(),
          u: integer(),
          b: integer()
        }

  @typedoc "State returned by `encode/2` and `encode/3`."
  @type encode_state :: %{
          c: [binary()],
          params: siop_params(),
          symbol_size: pos_integer(),
          k_prime: pos_integer(),
          source_symbols: [binary()]
        }

  @typedoc "Reasons returned by `decode/3` and friends."
  @type error_reason :: Decoder.reason()

  @doc """
  Encode source data for block of K source symbols.

  `data` is the source data as a binary.  `k` is the number of source
  symbols in the block.

  The `data` length must be exactly `k * symbol_size` (i.e. divisible by `k`)
  and must contain at least `k` bytes.  For automatic padding, use `encode/3`.

  Returns `{:ok, %{c: intermediate_symbols, params: siop_params,
  symbol_size: sym_size, k_prime: kp, source_symbols: source_syms}}`.
  """
  @spec encode(binary(), pos_integer()) :: {:ok, encode_state()} | {:error, error_reason()}
  def encode(data, k) do
    Validation.data!(data)
    Validation.k!(k)

    if rem(byte_size(data), k) != 0 do
      raise ArgumentError,
            "Data length must be an exact multiple of k. Use encode/3 for automatic chunking."
    end

    sym_size = div(byte_size(data), k)

    if sym_size < 1 do
      raise ArgumentError,
            "data must contain at least k = #{k} bytes (one byte per source symbol); " <>
              "use encode/3 with an explicit symbol size to pad"
    end

    do_encode(split_symbols(data, k, sym_size), k, sym_size)
  end

  @doc """
  Encode source data into exactly `k` source symbols of `sym_size`.

  Pads the data with trailing zeros if necessary to reach `k * sym_size`.
  Raises `ArgumentError` if the data is larger than `k * sym_size` (increase
  `k` or `symbol_size` to fit).
  """
  @spec encode(binary(), pos_integer(), pos_integer()) ::
          {:ok, encode_state()} | {:error, error_reason()}
  def encode(data, k, sym_size) do
    Validation.data!(data)
    Validation.k!(k)
    Validation.positive!(sym_size, :symbol_size)

    target_size = k * sym_size

    if byte_size(data) > target_size do
      raise ArgumentError,
            "data (#{byte_size(data)} bytes) does not fit in k * symbol_size = " <>
              "#{target_size} bytes; increase k or symbol_size"
    end

    do_encode(split_symbols(pad_to(data, target_size), k, sym_size), k, sym_size)
  end

  @doc """
  Generate one repair symbol for the given ISI.

  `c_syms` is the list of L intermediate symbols.
  `params` is the SIOP parameter map produced by `encode/2`.
  `isi` is the encoding symbol ID (any non-negative integer; use
  ISIs ≥ K' for true repair symbols, or < K' to regenerate source
  symbols). The symbol size is inferred from `c_syms`.

  Returns the repair symbol as a binary.
  """
  @spec repair([binary()], siop_params(), isi()) :: binary()
  def repair(c_syms, params, isi) do
    Validation.isi!(isi)
    Encoder.encode_symbol(c_syms, params, isi)
  end

  @doc """
  Decode received symbols to recover original source data.

  `received` is a list of `{isi, symbol_binary}` tuples.
  `k` is the number of source symbols in the original block.
  `data_size` (optional) truncates output to the original data size.

  Every candidate solution is verified against the full system it was
  built from — the LDPC/HDPC constraint rows as well as the received
  encoding rows — so a successful result is always consistent with the
  received data.  Returns `{:error, :singular}` when no verified
  solution could be found from the available symbols.
  """
  @spec decode([{isi(), binary()}], pos_integer(), non_neg_integer() | nil) ::
          {:ok, binary()} | {:error, error_reason()}
  def decode(received, k, data_size \\ nil) do
    Decoder.decode(received, k, data_size)
  end

  # ── Internal helpers ──────────────────────────────────────────────────

  defp do_encode(source_syms, k, sym_size) do
    kp = SIOP.values_for(k, :close).k

    case compute_intermediate(source_syms, k, kp, sym_size) do
      {:ok, c_syms, params} ->
        {:ok,
         %{
           c: c_syms,
           params: params,
           symbol_size: sym_size,
           k_prime: kp,
           source_symbols: source_syms
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

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

    # Solve A*C = D using 5-phase sparse solver, then verify the result
    # satisfies every constraint row before trusting it.
    with {:ok, c_syms} <- Solver.solve(constraint_rows, params, d_syms),
         :ok <- Solver.verify_solution(c_syms, constraint_rows, d_syms) do
      {:ok, c_syms, params}
    end
  end
end
