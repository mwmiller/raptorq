defmodule RaptorqConstraintMatrixTest do
  use ExUnit.Case
  alias Raptorq.ConstraintMatrix

  test "row count for small K'" do
    for k_prime <- [10, 18, 26, 60] do
      {rows, params} = ConstraintMatrix.build(k_prime)
      %{k: k, s: s, h: h, l: l} = params
      assert length(rows) == l
      assert l == k + s + h
    end
  end

  @tag timeout: 120_000
  test "row count for medium K'" do
    for k_prime <- [200, 1002] do
      {rows, params} = ConstraintMatrix.build(k_prime)
      %{k: k, s: s, h: h, l: l} = params
      assert length(rows) == l
      assert l == k + s + h
    end
  end

  @tag timeout: 120_000
  test "row count for maximum K'" do
    {rows, params} = ConstraintMatrix.build(56403)
    %{k: k, s: s, h: h, l: l} = params
    assert length(rows) == l
    assert l == k + s + h
  end

  test "LDPC rows contain only <<1>> values" do
    {rows, params} = ConstraintMatrix.build(10)
    %{s: s} = params

    for i <- 0..(s - 1) do
      row = Enum.at(rows, i)
      for {_col, val} <- row do
        assert val == <<1>>, "LDPC row #{i} has non-unity value #{inspect(val)}"
      end
    end
  end

  test "LDPC rows have I_S and G_LDPC,2 entries" do
    {rows, params} = ConstraintMatrix.build(10)
    %{b: b, s: s, w: w, p: p} = params

    for i <- 0..(s - 1) do
      row = Enum.at(rows, i)
      assert row[b + i] == <<1>>,
             "LDPC row #{i} missing I_S at column #{b + i}"
      assert row[w + rem(i, p)] == <<1>>,
             "LDPC row #{i} missing G_LDPC,2 at column #{w + rem(i, p)}"
      assert row[w + rem(i + 1, p)] == <<1>>,
             "LDPC row #{i} missing G_LDPC,2 at column #{w + rem(i + 1, p)}"
    end
  end

  test "HDPC rows have the correct I_H identity tail" do
    {rows, params} = ConstraintMatrix.build(18)
    %{s: s, h: h, k: k} = params
    kps = k + s

    for i <- 0..(h - 1) do
      row = Enum.at(rows, s + i)
      for j <- 0..(h - 1) do
        col = kps + j
        expected = if j == i, do: <<1>>, else: <<0>>
        actual = Map.get(row, col, <<0>>)
        assert actual == expected,
               "HDPC row #{i} col #{col}: expected #{inspect(expected)}, got #{inspect(actual)}"
      end
    end
  end

  test "G_ENC rows contain only <<1>> values" do
    {rows, params} = ConstraintMatrix.build(10)
    %{s: s, h: h, k: k} = params

    for i <- 0..(k - 1) do
      row = Enum.at(rows, s + h + i)
      for {_col, val} <- row do
        assert val == <<1>>, "G_ENC row #{i} has non-unity value #{inspect(val)}"
      end
    end
  end

  test "G_ENC rows match known tuple structure" do
    # ISI 10 is a repair symbol (K'=10, source ISIs are 0..9)
    # tuple(10, 10) = {d=2, a=15, b=15, d1=2, a1=10, b1=7}
    {rows, params} = ConstraintMatrix.build(10, [10])
    %{s: s, h: h, w: w} = params

    repair_row = Enum.at(rows, s + h)

    assert repair_row[15] == <<1>>, "Should have col 15 from b=15"
    assert repair_row[13] == <<1>>, "Should have col 13 from LT chain (b+a=30 mod w=17)"
    assert repair_row[w + 7] == <<1>>, "Should have col #{w + 7} from pb1=7"
    assert repair_row[w + 6] == <<1>>, "Should have col #{w + 6} from PI chain"
    assert map_size(repair_row) == 4
  end

  test "custom ISIs select specific rows" do
    {full_rows, params} = ConstraintMatrix.build(10)
    %{s: s, h: h} = params

    {partial_rows, _} = ConstraintMatrix.build(10, [0, 5])

    assert length(partial_rows) == s + h + 2
    for i <- 0..(s + h - 1) do
      assert Enum.at(partial_rows, i) == Enum.at(full_rows, i)
    end
    assert Enum.at(partial_rows, s + h) == Enum.at(full_rows, s + h)
    assert Enum.at(partial_rows, s + h + 1) == Enum.at(full_rows, s + h + 5)
  end

  test "HDPC rows are denser than LDPC rows" do
    {rows, params} = ConstraintMatrix.build(18)
    %{s: s, h: h, k: k} = params
    kps = k + s

    ldpc_entries = Enum.reduce(0..(s - 1), 0, fn i, acc ->
      acc + map_size(Enum.at(rows, i))
    end)
    avg_ldpc = ldpc_entries / max(s, 1)

    for i <- 0..(h - 1) do
      row = Enum.at(rows, s + i)
      ghdcp_count = Enum.count(row, fn {col, _} -> col < kps end)
      assert ghdcp_count > avg_ldpc,
             "HDPC row #{i} density (#{ghdcp_count}) should exceed avg LDPC (#{avg_ldpc})"
    end
  end

  test "repair symbol row can be generated" do
    isis = [0, 10]
    {rows, params} = ConstraintMatrix.build(10, isis)
    %{s: s, h: h} = params

    assert length(rows) == s + h + 2
    assert map_size(Enum.at(rows, s + h + 1)) > 0
  end
end
