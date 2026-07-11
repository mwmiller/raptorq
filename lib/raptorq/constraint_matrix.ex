defmodule Raptorq.ConstraintMatrix do
  @moduledoc """
  Builds the constraint matrix A from RFC 6330 Section 5.3.3.4.2.

  The matrix A is L×L over GF(2^8) satisfying A·C = D, where:
    - C: column vector of L intermediate symbols
    - D: S+H zero symbols followed by K' source symbols

  Matrix structure (Figure 5):
  ```
              B     S     U     H
           +-----+-----+-----+-----+
    S      |LDPC1| I_S |LDPC2|  0  |
           +-----+-----+-----+-----+
    H      |        G_HDPC     | I_H|
           +-----+-----+-----+-----+
    K'     |        G_ENC           |
           +-----+-----+-----+-----+
  ```

  Each row is a map `%{col_index => <<octet::8>>}`. LDPC and G_ENC rows
  contain only `<<1>>` entries; HDPC rows contain full GF(2^8) values.
  """

  alias Raptorq.{SIOP, Generators, Octet}

  @doc """
  Build the full constraint matrix A as a list of L row maps.

  `k_prime` is the extended source block symbol count.
  `encoded_isis` optionally specifies ISIs for G_ENC rows
  (defaults to all K' source symbols).

  Returns `{rows, params}`.
  """
  def build(k_prime, encoded_isis \\ nil) do
    params = SIOP.values_for(k_prime, :exact)
    %{b: b, s: s, h: h, w: w, p: p, p1: p1, k: k} = params

    ldpc = build_ldpc_rows(b, s, w, p)
    hdpc = build_hdpc_rows(k, s, h)
    isis = encoded_isis || Enum.to_list(0..(k - 1))
    g_enc = build_enc_rows(k, w, p, p1, isis)

    {ldpc ++ hdpc ++ g_enc, params}
  end

  # ── LDPC rows ────────────────────────────────────────────────────────
  #
  # Each LDPC row has 6 non-zero entries (all value 1):
  #   3 from G_LDPC,1 (first loop in §5.3.3.3)
  #   1 from I_S (the LDPC symbol itself)
  #   2 from G_LDPC,2 (second loop, PI symbol relationships)

  @doc false
  def build_ldpc_rows(b, s, w, p) do
    # G_LDPC,1: for each source symbol C[i] (0..B-1), three LDPC row updates
    #   a = 1 + floor(i/S), start at b = i%S, then b = (b+a)%S twice
    ldpc1 =
      for i <- 0..(b - 1), reduce: %{} do
        acc ->
          a = 1 + div(i, s)
          b0 = rem(i, s)
          acc
          |> add_to_row(b0, i)
          |> add_to_row(rem(b0 + a, s), i)
          |> add_to_row(rem(b0 + 2 * a, s), i)
      end

    for i <- 0..(s - 1) do
      row = %{}
      row = Map.put(row, b + i, <<1>>)                          # I_S
      row = Map.put(row, w + rem(i, p), <<1>>)                   # G_LDPC,2
      row = Map.put(row, w + rem(i + 1, p), <<1>>)               # G_LDPC,2
      row = merge_maps(row, Map.get(ldpc1, i, %{}))             # G_LDPC,1
      row
    end
  end

  # ── HDPC rows ────────────────────────────────────────────────────────
  #
  # G_HDPC = MT · GAMMA (§5.3.3.3).  A right-to-left recurrence
  # computes this in O(H·(K'+S)) instead of O(H·(K'+S)²):
  #
  #   G_HDPC[i, j] = α · G_HDPC[i, j+1] + MT[i, j]
  #
  # where α = 2 in GF(2^8).  This works because GAMMA is lower-
  # triangular with α^(j-k) on each diagonal.
  #
  # MT[i,j] for j < K'+S-1 selects two HDPC rows via Rand().
  # MT[i, K'+S-1] = α^i (used as the base case at the right edge).
  #
  # The I_H identity occupies the last H columns (column K'+S + i for
  # HDPC row i).

  @doc false
  def build_hdpc_rows(k, s, h) do
    kps = k + s
    alpha = <<2>>

    # Initialize rows with the rightmost column: G_HDPC[i, K'+S-1] = α^i
    rows = for i <- 0..(h - 1), do: %{kps - 1 => Octet.oexp(i)}

    # Work leftwards: G_HDPC[i,j] = α · G_HDPC[i,j+1] + MT[i,j]
    rows =
      Enum.reduce((kps - 2)..0//-1, rows, fn j, rows ->
        rows =
          Enum.map(rows, fn row ->
            prev = Map.get(row, j + 1, <<0>>)
            Map.put(row, j, Octet.omul(alpha, prev))
          end)

        r1 = Generators.rand(j + 1, 6, h)
        r2 = Generators.rand(j + 1, 7, h - 1)
        i1 = r1
        i2 = rem(r1 + r2 + 1, h)

        rows
        |> List.update_at(i1, fn row ->
          cur = Map.get(row, j, <<0>>)
          Map.put(row, j, Octet.oadd(cur, <<1>>))
        end)
        |> List.update_at(i2, fn row ->
          cur = Map.get(row, j, <<0>>)
          Map.put(row, j, Octet.oadd(cur, <<1>>))
        end)
      end)

    # Append I_H: column K'+S+i has value 1 for each row i
    rows |> Enum.with_index() |> Enum.map(fn {row, i} ->
      Map.put(row, kps + i, <<1>>)
    end)
  end

  # ── G_ENC rows ───────────────────────────────────────────────────────
  #
  # Each source symbol at ISI X produces a Tuple[K', X] (§5.3.5.4)
  # specifying (d, a, b, d1, a1, b1).  The Enc[] function (§5.3.5.3)
  # generates the encoding symbol by summing these intermediate symbols:
  #
  #   1. Start at column b (LT symbol, 0 ≤ b < w)
  #   2. Repeat d-1 times: b = (b + a) % w
  #   3. Move b1 past the PI boundary: while b1 ≥ p, b1 = (b1 + a1) % p1
  #   4. Start at column w + b1 (PI symbol)
  #   5. Repeat d1-1 times: b1 = (b1 + a1) % p1 with boundary check

  @doc false
  def build_enc_rows(k, w, p, p1, isis) do
    for x <- isis do
      {d, a, b, d1, a1, b1} = Generators.tuple(k, x)

      pb1 = move_down(b1, a1, p, p1)

      [b | lt_chain_indices(b, a, w, max(0, d - 1))]
      |> Enum.concat([w + pb1])
      |> Enum.concat(pi_chain_indices(pb1, a1, p, p1, w, max(0, d1 - 1)))
      |> MapSet.new()
      |> Enum.reduce(%{}, fn col, acc -> Map.put(acc, col, <<1>>) end)
    end
  end

  defp move_down(b1, _a1, p, _p1) when b1 < p, do: b1
  defp move_down(b1, a1, p, p1), do: move_down(rem(b1 + a1, p1), a1, p, p1)

  defp lt_chain_indices(b, a, w, remaining) do
    lt_chain_indices(b, a, w, remaining, [])
  end

  defp lt_chain_indices(_b, _a, _w, 0, acc), do: :lists.reverse(acc)
  defp lt_chain_indices(b, a, w, remaining, acc) do
    idx = rem(b + a, w)
    lt_chain_indices(idx, a, w, remaining - 1, [idx | acc])
  end

  defp pi_chain_indices(start, a1, p, p1, w, remaining) do
    pi_chain_indices(start, a1, p, p1, w, remaining, [])
  end

  defp pi_chain_indices(_prev, _a1, _p, _p1, _w, 0, acc), do: :lists.reverse(acc)
  defp pi_chain_indices(prev, a1, p, p1, w, remaining, acc) do
    raw = rem(prev + a1, p1) |> move_down(a1, p, p1)
    pi_chain_indices(raw, a1, p, p1, w, remaining - 1, [w + raw | acc])
  end

  # ── Map helpers ──────────────────────────────────────────────────────

  defp add_to_row(rows, row_idx, col_idx) do
    Map.update(rows, row_idx, %{col_idx => <<1>>}, fn existing ->
      Map.put(existing, col_idx, <<1>>)
    end)
  end

  defp merge_maps(a, b) do
    Map.merge(a, b, fn _k, v1, v2 -> Octet.oadd(v1, v2) end)
  end

  # Used in tests for verification
  @doc false
  def rows_to_mapset(rows) do
    Enum.map(rows, fn row -> MapSet.new(Map.keys(row)) end)
  end
end
