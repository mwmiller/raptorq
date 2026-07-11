defmodule Raptorq.Solver do
  @moduledoc """
  Solve A·C = D for the L intermediate symbols C over GF(2⁸).

  ## Current implementation: dense Gauss-Jordan

  Converts the sparse constraint matrix to a dense L×L octet matrix
  and runs full elimination.  The `Enum.at`/`List.replace_at` calls
  on list-of-lists add O(L) overhead per access, making the effective
  complexity O(L⁴) for list traversal + O(L³) for arithmetic.

  Benchmarks:
    K=10   L=27     1ms
    K=200  L=233  322ms
    K=500  L=558  3.7s
    K=1000 L=1071 23s

  For K > ~500 a 5-phase sparse solver (RFC 6330 §5.4.2.2) tracking
  row/column ops on sparse maps is needed instead.  The old 5-phase
  prototype hit a column-swap contamination bug in Phase 1; see git
  history for details.
  """

  alias Raptorq.Octet

  defstruct [:A, :D, :L, :params]

  @doc """
  Solve A·C = D for the intermediate symbols C.

  `constraint_rows` — first L rows of the constraint matrix (list of
  `%{col => <<val>>}` maps).

  `params` — SIOP parameter map (from `Raptorq.SIOP.values_for/2`).

  `d_symbols` — column vector D of L symbols (each a binary of equal
  length).

  Returns `{:ok, c_syms}` where `c_syms` is a list of L intermediate
  symbols, or `{:error, :singular}` if the matrix is rank-deficient.
  """
  def solve(constraint_rows, params, d_symbols, opts \\ []) do
    %{l: l} = params

    a = Enum.map(constraint_rows, fn row -> Map.new(row) end)

    solver = %__MODULE__{A: a, D: d_symbols, L: l, params: params}

    case execute(solver) do
      {:ok, solver} ->
        d = Map.get(solver, :D)

        if opts[:debug] do
          {:ok, d, solver}
        else
          {:ok, d}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Dense Gauss-Jordan ────────────────────────────────────────────────

  defp execute(solver) do
    %{A: a, D: d, L: l} = solver

    dense =
      for i <- 0..(l - 1) do
        row_map = Enum.at(a, i, %{})
        for j <- 0..(l - 1), do: Map.get(row_map, j, <<0>>)
      end

    case ge_full(dense, d, l, 0) do
      {:ok, c_syms} -> {:ok, %{solver | D: c_syms}}
      err -> err
    end
  end

  defp ge_full(_a, d, n, col) when col >= n, do: {:ok, d}

  defp ge_full(a, d, n, col) do
    pivot_idx = Enum.find_index(Enum.drop(a, col), fn row -> Enum.at(row, col) != <<0>> end)

    if pivot_idx == nil do
      {:error, :singular}
    else
      pivot = col + pivot_idx

      {a, d} =
        if pivot != col do
          {swap_list(a, col, pivot), swap_list(d, col, pivot)}
        else
          {a, d}
        end

      pivot_val = a |> Enum.at(col) |> Enum.at(col)

      {a, d} =
        if pivot_val != <<1>> do
          inv = Octet.odiv(<<1>>, pivot_val)
          {List.update_at(a, col, fn row -> Enum.map(row, &Octet.omul(&1, inv)) end),
           List.update_at(d, col, &Octet.smul(&1, inv))}
        else
          {a, d}
        end

      pivot_row = Enum.at(a, col)
      p_sym = Enum.at(d, col)

      {a, d} =
        Enum.reduce(Enum.reject(0..(n - 1), &(&1 == col)), {a, d}, fn row, {a_acc, d_acc} ->
          f = a_acc |> Enum.at(row) |> Enum.at(col)

          if f != <<0>> do
            new_row = Enum.zip_with(Enum.at(a_acc, row), pivot_row, fn v, pv ->
              Octet.oadd(v, Octet.omul(pv, f))
            end)

            new_d = Octet.sadd(Enum.at(d_acc, row), Octet.smul(p_sym, f))
            {List.replace_at(a_acc, row, new_row), List.replace_at(d_acc, row, new_d)}
          else
            {a_acc, d_acc}
          end
        end)

      ge_full(a, d, n, col + 1)
    end
  end

  # ── Utilities ─────────────────────────────────────────────────────────

  defp swap_list(list, i, j) when i == j, do: list

  defp swap_list(list, i, j) do
    min_i = min(i, j)
    max_i = max(i, j)
    {left, [vi | mid]} = Enum.split(list, min_i)
    {mid2, [vj | right]} = Enum.split(mid, max_i - min_i - 1)
    left ++ [vj | mid2] ++ [vi | right]
  end
end
