defmodule RaptorqSolverTest do
  use ExUnit.Case
  alias Raptorq.{ConstraintMatrix, Solver, Octet}

  @symbol_size 4

  # ── Dense solver: convert A to dense octet matrix, track ops, apply to D ──

  defp build_dense_a(rows, l) do
    for i <- 0..(l - 1) do
      row = Enum.at(rows, i, %{})
      for j <- 0..(l - 1), do: Map.get(row, j, <<0>>)
    end
  end

  defp build_d_syms(rows, c_syms) do
    Enum.map(rows, fn row ->
      Enum.reduce(row, <<0::size(@symbol_size)-unit(8)>>, fn {col, val}, acc ->
        Octet.sadd(acc, Octet.smul(Enum.at(c_syms, col), val))
      end)
    end)
  end

  defp dense_solve(rows, params, d_syms) do
    %{l: l} = params
    a = build_dense_a(rows, l)
    case do_ge(a, l, 0, []) do
      {:ok, ops} -> {:ok, apply_ops_to_d(d_syms, Enum.reverse(ops))}
      err -> err
    end
  end

  defp do_ge(_a, n, col, ops) when col >= n, do: {:ok, ops}

  defp do_ge(a, n, col, ops) do
    pivot_idx = Enum.find_index(Enum.drop(a, col), fn row -> Enum.at(row, col) != <<0>> end)
    if pivot_idx == nil, do: {:error, :singular}, else: eliminate(a, n, col, ops, col + pivot_idx)
  end

  defp eliminate(a, n, col, ops, col), do: do_eliminate(a, n, col, ops)

  defp eliminate(a, n, col, ops, pivot) do
    a = swap_row(a, col, pivot)
    do_eliminate(a, n, col, [{:swap, col, pivot} | ops])
  end

  defp do_eliminate(a, n, col, ops) do
    val = a |> Enum.at(col) |> Enum.at(col)

    {a, ops} = if val != <<1>> do
      inv = Octet.odiv(<<1>>, val)
      {scale_row(a, col, inv), [{:scale, col, inv} | ops]}
    else
      {a, ops}
    end

    pivot = Enum.at(a, col)

    {a, ops} =
      Enum.reduce(Enum.reject(0..(n - 1), &(&1 == col)), {a, ops}, fn row, {a_acc, ops_acc} ->
        f = a_acc |> Enum.at(row) |> Enum.at(col)
        if f != <<0>> do
          new_row = Enum.zip_with(Enum.at(a_acc, row), pivot, fn v, pv ->
            Octet.oadd(v, Octet.omul(pv, f))
          end)
          {List.replace_at(a_acc, row, new_row), [{:fma, col, row, f} | ops_acc]}
        else
          {a_acc, ops_acc}
        end
      end)

    do_ge(a, n, col + 1, ops)
  end

  defp scale_row(a, row, inv) do
    List.update_at(a, row, fn r -> Enum.map(r, &Octet.omul(&1, inv)) end)
  end

  defp swap_row(a, i, j) do
    vi = Enum.at(a, i)
    vj = Enum.at(a, j)
    a |> List.replace_at(i, vj) |> List.replace_at(j, vi)
  end

  defp swap_list(list, i, j) when i == j, do: list
  defp swap_list(list, i, j) do
    min_i = min(i, j)
    max_i = max(i, j)
    {left, [vi | mid]} = Enum.split(list, min_i)
    {mid2, [vj | right]} = Enum.split(mid, max_i - min_i - 1)
    left ++ [vj | mid2] ++ [vi | right]
  end

  defp apply_ops_to_d(d, []), do: d
  defp apply_ops_to_d(d, [{:swap, r1, r2} | rest]) do
    apply_ops_to_d(swap_list(d, r1, r2), rest)
  end
  defp apply_ops_to_d(d, [{:scale, row, scalar} | rest]) do
    apply_ops_to_d(
      List.replace_at(d, row, Octet.smul(Enum.at(d, row), scalar)),
      rest
    )
  end
  defp apply_ops_to_d(d, [{:fma, src, dest, factor} | rest]) do
    new_dest = Octet.sadd(Enum.at(d, dest), Octet.smul(Enum.at(d, src), factor))
    apply_ops_to_d(List.replace_at(d, dest, new_dest), rest)
  end

  # ── Tests ─────────────────────────────────────────────────────────────

  test "dense solver round-trip for K'=10" do
    {rows, params} = ConstraintMatrix.build(10)
    %{l: l} = params
    c_syms = for _ <- 1..l, do: :crypto.strong_rand_bytes(@symbol_size)
    d_syms = build_d_syms(rows, c_syms)

    assert {:ok, recovered} = dense_solve(rows, params, d_syms)
    assert length(recovered) == l

    Enum.zip(c_syms, recovered) |> Enum.each(fn {orig, recv} ->
      assert orig == recv
    end)
  end

  test "solver round-trip for K'=10" do
    {rows, params} = ConstraintMatrix.build(10)
    %{l: l} = params
    c_syms = for _ <- 1..l, do: :crypto.strong_rand_bytes(@symbol_size)
    d_syms = build_d_syms(rows, c_syms)

    assert {:ok, recovered} = Solver.solve(rows, params, d_syms)
    assert length(recovered) == l

    Enum.zip(c_syms, recovered) |> Enum.each(fn {orig, recv} ->
      assert orig == recv
    end)
  end
end
