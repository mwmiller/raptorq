defmodule Raptorq.Solver do
  @moduledoc """
  RFC 6330 §5.4.2 — 5-phase sparse Gaussian elimination.

  Solves A·C = D for intermediate symbols C given constraint matrix A
  and received encoding symbols D, using the sparse 5-phase algorithm
  that is O(L²) instead of O(L³).

  ## Algorithm outline

  Phase 1 — Forward elimination on I+U columns.
  Phase 2 — Dense GE on U columns of residual rows.
  Phase 3 — Eliminate U columns from first `i` rows (Errata 9/10).
  Phase 4 — Eliminate I columns from rows `i..M-1`.
  Phase 5 — Final scaling and below-diagonal elimination.

  Operations applied to A during Phase 1 are tracked and replayed
  on D during Phase 3 (reverse) and Phase 5 (forward), per Errata 9.
  """

  alias Raptorq.Octet

  defstruct A: [], D: [], c: [], d: [], i: 0, u: 0, L: 0, M: 0, params: %{}

  @doc """
  Solve A·C = D using the 5-phase algorithm.
  """
  def solve(constraint_rows, params, d_symbols) do
    %{l: l, p: p} = params
    m = length(constraint_rows)

    a = Enum.map(constraint_rows, fn row -> Map.new(row) end)

    solver = %__MODULE__{
      A: a,
      D: d_symbols,
      c: Enum.to_list(0..(l - 1)),
      d: Enum.to_list(0..(m - 1)),
      i: 0,
      u: p,
      L: l,
      M: m,
      params: params
    }

    case first_phase(solver) do
      {:ok, s1} ->
        case second_phase(s1) do
          {:ok, s2} ->
            s3 = third_phase(s2)
            s5 = fifth_phase(s3)
            s4 = fourth_phase(s5)
            {:ok, extract_intermediate(s4)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Phase 1 — §5.4.2.2 ────────────────────────────────────────────────

  defp first_phase(%{i: i, u: u, L: l} = solver) when i + u >= l do
    {:ok, solver}
  end

  defp first_phase(solver) do
    %{i: i, u: u, L: l, A: a, M: m} = solver
    v_end = l - u

    # 1. Find candidates: rows with at least one non-zero V-column entry
    non_hdpc = get_non_hdpc_rows(solver)

    candidates =
      Enum.filter(non_hdpc, fn row ->
        has_v(a, row, i, v_end)
      end)

    candidates =
      if candidates == [] do
        get_hdpc_rows(solver)
        |> Enum.filter(fn row -> has_v(a, row, i, v_end) end)
      else
        candidates
      end

    if candidates == [] do
      {:error, :singular}
    else
      # 2. Find minimum degree r within V range
      r = candidates |> Enum.map(&v_count(a, &1, i, v_end)) |> Enum.min()

      # 3. Select and swap row to position i
      chosen = select_row(a, candidates, r, i, v_end)
      solver = swap_row_to_position(solver, i, chosen)

      # 4. Arrange columns: move r non-zero V cols to I (1) and U (r-1)
      solver = arrange_columns(solver, i, r)

      # 5. Eliminate pivot column i from rows below
      %{A: a2, D: d2} = solver
      pivot_val = Map.get(Enum.at(a2, i, %{}), i, <<0>>)

      {a, d} = eliminate_below(a2, d2, i, pivot_val, m)

      solver = %{solver | A: a, D: d}
      solver = %{solver | i: i + 1, u: u + r - 1}

      first_phase(solver)
    end
  end

  # Forward-eliminate `pivot_col` from every row below it, applying the
  # same scaled update to the sparse matrix `a` and the symbol vector `d`.
  defp eliminate_below(a, d, pivot_col, pivot_val, m) do
    if pivot_val == <<0>> do
      {a, d}
    else
      (pivot_col + 1)..(m - 1)
      |> Enum.reduce({a, d}, &eliminate_pivot_row(&1, pivot_col, pivot_val, &2))
    end
  end

  defp eliminate_pivot_row({a_acc, d_acc}, pivot_col, pivot_val, row) do
    beta = a_acc |> Enum.at(row, %{}) |> Map.get(pivot_col, <<0>>)

    if beta == <<0>> do
      {a_acc, d_acc}
    else
      scalar = Octet.odiv(beta, pivot_val)
      a_acc = fma(a_acc, pivot_col, row, scalar)

      d_acc =
        Octet.sadd(Enum.at(d_acc, row), Octet.smul(Enum.at(d_acc, pivot_col), scalar))
        |> then(fn v -> List.replace_at(d_acc, row, v) end)

      {a_acc, d_acc}
    end
  end

  # ── Row selection heuristics ──────────────────────────────────────────

  defp select_row(a, candidates, r, v_start, v_end) do
    if r == 2 do
      rows_with_2 =
        Enum.filter(candidates, fn row ->
          v_count(a, row, v_start, v_end) == 2
        end)

      if rows_with_2 != [] do
        # Graph-theoretic selection
        select_graph_row(a, rows_with_2, v_start, v_end)
      else
        Enum.min_by(candidates, &map_size(Enum.at(a, &1, %{})))
      end
    else
      Enum.min_by(candidates, &map_size(Enum.at(a, &1, %{})))
    end
  end

  defp select_graph_row(a, rows, v_start, v_end) do
    edges =
      Enum.flat_map(rows, fn row ->
        row_map = Enum.at(a, row, %{})

        ones =
          row_map
          |> Enum.filter(fn {col, val} ->
            col >= v_start and col < v_end and val == <<1>>
          end)
          |> Enum.map(fn {col, _} -> col end)

        case ones do
          [c1, c2] -> [{c1, c2}]
          _ -> []
        end
      end)

    if edges == [] do
      hd(rows)
    else
      nodes = edges |> Enum.flat_map(fn {a, b} -> [a, b] end) |> Enum.uniq()

      adj =
        Enum.reduce(edges, %{}, fn {a, b}, acc ->
          acc
          |> Map.update(a, [b], fn es -> [b | es] end)
          |> Map.update(b, [a], fn es -> [a | es] end)
        end)

      visited = MapSet.new()
      components = find_components(nodes, adj, visited, [])

      largest = Enum.max_by(components, &length/1)
      pivot_col = hd(largest)

      Enum.find(rows, fn row -> Map.get(Enum.at(a, row, %{}), pivot_col, <<0>>) != <<0>> end) ||
        hd(rows)
    end
  end

  defp find_components([], _adj, _visited, comps), do: comps

  defp find_components([node | rest], adj, visited, comps) do
    if MapSet.member?(visited, node) do
      find_components(rest, adj, visited, comps)
    else
      {comp, new_visited} = traverse([node], adj, MapSet.put(visited, node), [node])
      find_components(rest, adj, new_visited, [comp | comps])
    end
  end

  defp traverse([], _adj, visited, comp), do: {comp, visited}

  defp traverse([node | queue], adj, visited, comp) do
    neighbors = Map.get(adj, node, [])
    new_nodes = Enum.reject(neighbors, fn n -> MapSet.member?(visited, n) end)
    new_visited = Enum.reduce(new_nodes, visited, fn n, v -> MapSet.put(v, n) end)
    traverse(queue ++ new_nodes, adj, new_visited, comp ++ new_nodes)
  end

  # ── Row/column helpers ────────────────────────────────────────────────

  defp swap_row_to_position(solver, pos, pos), do: solver

  defp swap_row_to_position(solver, pos, chosen) do
    %{A: a, D: d, d: d_perm} = solver

    %{
      solver
      | A: swap_list(a, pos, chosen),
        D: swap_list(d, pos, chosen),
        d: swap_list(d_perm, pos, chosen)
    }
  end

  defp arrange_columns(solver, pivot_row, _r) do
    %{A: a, i: i, u: u, L: l} = solver
    v_end = l - u
    row_map = Enum.at(a, pivot_row, %{})

    nz_cols =
      row_map
      |> Enum.filter(fn {col, val} ->
        col >= i and col < v_end and val != <<0>>
      end)
      |> Enum.map(fn {col, _} -> col end)
      |> Enum.sort()

    arrange_v_columns(solver, nz_cols)
  end

  # Move the non-zero V columns of the pivot row into the I/U structure:
  # the first becomes the I column at position `i`, the rest fill the U
  # columns from the right.
  defp arrange_v_columns(solver, []), do: solver

  defp arrange_v_columns(solver, [first | rest]) do
    %{i: i, u: u, L: l} = solver
    v_end = l - u

    solver = if first != i, do: swap_columns(solver, first, i), else: solver

    Enum.reduce(Enum.with_index(rest), solver, fn {col, idx}, s ->
      dest = v_end - 1 - idx
      if col != dest, do: swap_columns(s, col, dest), else: s
    end)
  end

  defp swap_columns(solver, col1, col2) do
    %{A: a, c: c_perm} = solver

    new_a =
      Enum.map(a, fn row_map ->
        v1 = Map.get(row_map, col1, :__missing__)
        v2 = Map.get(row_map, col2, :__missing__)

        row_map
        |> maybe_delete(col1, v1)
        |> maybe_delete(col2, v2)
        |> maybe_put(col2, v1)
        |> maybe_put(col1, v2)
      end)

    %{solver | A: new_a, c: swap_list(c_perm, col1, col2)}
  end

  defp maybe_delete(map, _col, :__missing__), do: map
  defp maybe_delete(map, col, _val), do: Map.delete(map, col)

  defp maybe_put(map, _col, :__missing__), do: map
  defp maybe_put(map, col, val), do: Map.put(map, col, val)

  # ── Row queries ───────────────────────────────────────────────────────

  defp get_non_hdpc_rows(%{M: m, params: %{s: s, h: h}}) do
    Enum.to_list(0..(m - 1)) |> Enum.reject(fn row -> row >= s and row < s + h end)
  end

  defp get_hdpc_rows(%{params: %{s: s, h: h}}) when h > 0 do
    Enum.to_list(s..(s + h - 1))
  end

  defp get_hdpc_rows(_), do: []

  defp has_v(a, row, v_start, v_end) do
    row_map = Enum.at(a, row, %{})

    Enum.any?(row_map, fn {col, val} ->
      col >= v_start and col < v_end and val != <<0>>
    end)
  end

  defp v_count(a, row, v_start, v_end) do
    row_map = Enum.at(a, row, %{})

    Enum.count(row_map, fn {col, val} ->
      col >= v_start and col < v_end and val != <<0>>
    end)
  end

  # ── FMA and D operations ──────────────────────────────────────────────

  defp fma(a, src, dest, scalar) do
    src_row = Enum.at(a, src, %{})
    dest_row = Enum.at(a, dest, %{})

    # Map.merge only calls resolver for keys in BOTH maps
    # Keys only in src would get src value, not scalar * src value
    # Manually apply scalar to all src entries first
    scaled_src = Map.new(src_row, fn {c, v} -> {c, Octet.omul(v, scalar)} end)

    merged =
      Map.merge(scaled_src, dest_row, fn _col, v_prod, v_dest ->
        result = Octet.oadd(v_prod, v_dest)
        if result == <<0>>, do: :__delete__, else: result
      end)

    Map.reject(merged, fn {_k, v} -> v == :__delete__ end)
    |> then(fn cleaned -> List.replace_at(a, dest, cleaned) end)
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

  @doc false
  def run_phases(rows, params, d_syms) do
    %{l: l, p: p} = params
    m = length(rows)
    a = Enum.map(rows, fn row -> Map.new(row) end)

    s = %__MODULE__{
      A: a,
      D: d_syms,
      c: Enum.to_list(0..(l - 1)),
      d: Enum.to_list(0..(m - 1)),
      i: 0,
      u: p,
      L: l,
      M: m,
      params: params
    }

    case first_phase(s) do
      {:ok, s1} ->
        case second_phase(s1) do
          {:ok, s2} ->
            s3 = third_phase(s2)
            s5p = fifth_phase(s3)
            s4 = fourth_phase(s5p)
            {:ok, s1, s2, s3, s4, s5p, Map.get(s4, :c)}

          err ->
            err
        end

      err ->
        err
    end
  end

  # ── Phase 2 — §5.4.2.3 ────────────────────────────────────────────────

  defp second_phase(%{u: u} = solver) when u == 0, do: {:ok, truncate_matrix(solver)}

  defp second_phase(solver) do
    %{i: i, u: u, L: l, M: m, A: a, D: d} = solver
    u_start = l - u

    # Step0: Eliminate I-set entries from U-lower rows
    # After Phase 1, rows i..M-1 may have non-zero entries in I columns 0..i-1
    # (introduced by column swaps in Phase 1).  Use I-rows to eliminate them.
    {a, d} = eliminate_i_columns(a, d, i, m)

    solver = %{solver | A: a, D: d}
    %{A: a, D: d, i: i, u: u, L: l, M: m, d: d_perm} = solver

    # Extract U-lower rows (positions i..M-1)
    u_lower_pos = Enum.to_list(i..(m - 1))

    u_lower =
      Enum.map(u_lower_pos, fn pos ->
        row_map = Enum.at(a, pos, %{})
        for col <- u_start..(l - 1), do: Map.get(row_map, col, <<0>>)
      end)

    # Dense GE on U matrix (track ops, apply to A and D)
    reduce_result =
      try do
        {:ok,
         Enum.reduce(0..(u - 1), {u_lower, a, d, d_perm}, fn col, acc ->
           ge_column(col, acc, u, u_lower_pos)
         end)}
      catch
        {:singular, col} -> {:error, {:singular, col}}
      end

    case reduce_result do
      {:ok, {_, final_a, final_d, final_d_perm}} ->
        {a2, final_d, final_d_perm} =
          write_u_identity(final_a, final_d, final_d_perm, u, u_start, u_lower_pos)

        {:ok, truncate_matrix(%{solver | A: a2, D: final_d, d: final_d_perm})}

      {:error, _} = err ->
        err
    end
  end

  # Step 0 of Phase 2: clear any I-column entries that Phase 1's column
  # swaps left in the U-lower rows, using the now-pivoted I rows.
  defp eliminate_i_columns(a, d, i, m) do
    if i <= 0 do
      {a, d}
    else
      Enum.reduce(0..(i - 1), {a, d}, fn i_col, {a_acc, d_acc} ->
        pivot_val = a_acc |> Enum.at(i_col, %{}) |> Map.get(i_col, <<1>>)

        Enum.reduce(i..(m - 1), {a_acc, d_acc}, fn u_row, {a2, d2} ->
          val = a2 |> Enum.at(u_row, %{}) |> Map.get(i_col, <<0>>)

          if val != <<0>> do
            sc = Octet.odiv(val, pivot_val)

            {fma(a2, i_col, u_row, sc),
             d2 |> List.update_at(u_row, &Octet.sadd(&1, Octet.smul(Enum.at(d2, i_col), sc)))}
          else
            {a2, d2}
          end
        end)
      end)
    end
  end

  # One column of the dense Gaussian elimination over the U submatrix.
  defp ge_column(col, {r_a, a_a, d_a, dp_a}, u, u_lower_pos) do
    pivot_idx = r_a |> Enum.drop(col) |> Enum.find_index(&(Enum.at(&1, col) != <<0>>))

    if pivot_idx == nil do
      throw({:singular, col})
    end

    pivot_actual = col + pivot_idx

    {r_a, a_a, d_a, dp_a} =
      if pivot_actual != col do
        src_pos = Enum.at(u_lower_pos, col)
        src_pivot_pos = Enum.at(u_lower_pos, pivot_actual)
        {swap_list(r_a, col, pivot_actual), swap_list(a_a, src_pos, src_pivot_pos),
         swap_list(d_a, src_pos, src_pivot_pos), swap_list(dp_a, src_pos, src_pivot_pos)}
      else
        {r_a, a_a, d_a, dp_a}
      end

    pivot_val = r_a |> Enum.at(col) |> Enum.at(col)

    {r_a, a_a, d_a} =
      if pivot_val != <<1>> do
        inv = Octet.odiv(<<1>>, pivot_val)

        {r_a |> List.update_at(col, fn r -> Enum.map(r, &Octet.omul(&1, inv)) end),
         scale_sparse(a_a, Enum.at(u_lower_pos, col), inv),
         d_a |> List.update_at(Enum.at(u_lower_pos, col), &Octet.smul(&1, inv))}
      else
        {r_a, a_a, d_a}
      end

    pivot_row = Enum.at(r_a, col)

    {r_a, a_a, d_a} =
      Enum.reject(0..(u - 1), &(&1 == col))
      |> Enum.reduce({r_a, a_a, d_a}, fn r, {r2_a, a2_a, d2_a} ->
        val = r2_a |> Enum.at(r) |> Enum.at(col)

        if val != <<0>> do
          new_r =
            Enum.zip_with(Enum.at(r2_a, r), pivot_row, fn v, pv ->
              Octet.oadd(v, Octet.omul(pv, val))
            end)

          {List.replace_at(r2_a, r, new_r),
           fma(a2_a, Enum.at(u_lower_pos, col), Enum.at(u_lower_pos, r), val),
           d2_a
           |> List.update_at(Enum.at(u_lower_pos, r), &Octet.sadd(&1, Octet.smul(Enum.at(d2_a, Enum.at(u_lower_pos, col)), val)))}
        else
          {r2_a, a2_a, d2_a}
        end
      end)

    {r_a, a_a, d_a, dp_a}
  end

  # Write the identity block back into the U columns of each U-lower row.
  defp write_u_identity(final_a, final_d, final_d_perm, u, u_start, u_lower_pos) do
    a2 =
      Enum.reduce(0..(u - 1), final_a, fn offset, a_acc ->
        act_row = Enum.at(u_lower_pos, offset)

        new_row =
          Enum.reduce(0..(u - 1), final_a |> Enum.at(act_row, %{}), fn col_off, r ->
            c = u_start + col_off
            if offset == col_off, do: Map.put(r, c, <<1>>), else: Map.delete(r, c)
          end)

        List.replace_at(a_acc, act_row, new_row)
      end)

    {a2, final_d, final_d_perm}
  end

  defp scale_sparse(a, row, scalar) do
    row_map = Enum.at(a, row, %{})
    new_row = Map.new(row_map, fn {col, val} -> {col, Octet.omul(val, scalar)} end)
    List.replace_at(a, row, new_row)
  end

  defp truncate_matrix(solver) do
    %{A: a, D: d, L: l} = solver
    %{solver | A: Enum.take(a, l), D: Enum.take(d, l), M: l}
  end

  # ── Phase 3 — §5.4.2.4 ────────────────────────────────────────────────

  defp third_phase(solver) do
    %{i: i, L: l, u: u} = solver
    u_start = l - u

    # Eliminate U columns from rows 0..i-1 using the U-identity rows.
    for row <- 0..(i - 1), reduce: solver do
      s ->
        u_nz =
          s
          |> Map.get(:A)
          |> Enum.at(row, %{})
          |> Enum.filter(fn {col, val} -> col >= u_start and val != <<0>> end)

        eliminate_u_from_row(s, row, u_nz)
    end
  end

  # ── Phase 4 — §5.4.2.5 ────────────────────────────────────────────────

  defp fourth_phase(solver) do
    %{i: i, M: m, L: l, u: u} = solver
    u_start = l - u

    for row <- i..(m - 1), reduce: solver do
      s ->
        u_nz =
          s
          |> Map.get(:A)
          |> Enum.at(row, %{})
          |> Enum.filter(fn {col, val} ->
            col >= u_start and val != <<0>> and col != row
          end)

        s = eliminate_u_from_row(s, row, u_nz)

        i_nz =
          s
          |> Map.get(:A)
          |> Enum.at(row, %{})
          |> Enum.filter(fn {col, _} -> col < i end)

        eliminate_i_from_row(s, row, i_nz)
    end
  end

  # ── Phase 5 — Full Gauss-Jordan on I×I submatrix ──────────────────

  defp fifth_phase(solver) do
    %{i: i} = solver

    for pivot <- 0..(i - 1), reduce: solver do
      s -> s |> scale_pivot_row(pivot) |> eliminate_pivot_column(pivot)
    end
  end

  # Scale the `pivot` row of the I submatrix to a unit pivot, applying
  # the same inverse to D.
  defp scale_pivot_row(s, pivot) do
    diag = s |> Map.get(:A) |> Enum.at(pivot, %{}) |> Map.get(pivot, <<0>>)

    if diag != <<1>> and diag != <<0>> do
      inv = Octet.odiv(<<1>>, diag)

      s
      |> Map.update!(:A, &scale_sparse(&1, pivot, inv))
      |> Map.update!(:D, &List.update_at(&1, pivot, fn sym -> Octet.smul(sym, inv) end))
    else
      s
    end
  end

  # Eliminate the `pivot` column from every other I row.
  defp eliminate_pivot_column(s, pivot) do
    for r <- 0..(s.i - 1), r != pivot, reduce: s do
      s2 ->
        %{A: a2, D: d2} = s2
        beta = a2 |> Enum.at(r, %{}) |> Map.get(pivot, <<0>>)

        if beta != <<0>> do
          %{
            s2
            | A: fma(a2, pivot, r, beta),
              D: List.update_at(d2, r, &Octet.sadd(&1, Octet.smul(Enum.at(d2, pivot), beta)))
          }
        else
          s2
        end
    end
  end

  # FMA every non-zero U/I-column entry of `row` into D (and A), the
  # shared elimination step used by Phases 3 and 4.
  defp eliminate_u_from_row(solver, row, nz) do
    Enum.reduce(nz, solver, fn {col, val}, s2 ->
      d = Map.get(s2, :D)
      a2 = fma(Map.get(s2, :A), col, row, val)
      d2 = d |> List.update_at(row, &Octet.sadd(&1, Octet.smul(Enum.at(d, col), val)))
      %{s2 | A: a2, D: d2}
    end)
  end

  defp eliminate_i_from_row(solver, row, nz) do
    Enum.reduce(nz, solver, fn {col, _}, s2 ->
      a = Map.get(s2, :A)
      val = a |> Enum.at(row, %{}) |> Map.get(col, <<0>>)

      if val != <<0>> do
        pivot_val = a |> Enum.at(col, %{}) |> Map.get(col, <<1>>)
        sc = Octet.odiv(val, pivot_val)
        d = Map.get(s2, :D)
        a2 = fma(a, col, row, sc)
        d2 = d |> List.update_at(row, &Octet.sadd(&1, Octet.smul(Enum.at(d, col), sc)))
        %{s2 | A: a2, D: d2}
      else
        s2
      end
    end)
  end

  # ── Extract intermediate symbols ──────────────────────────────────────

  defp extract_intermediate(solver) do
    %{D: d_syms, c: c_perm, L: l} = solver
    # D[j] = C'[j] (solution in permuted space)
    # Original: A * C = D. After col swaps: A' * C' = D where A'[i][j] = A[i][c[j]]
    # C'[j] = C[c[j]], so C[c[j]] = C'[j] = D[j]
    result = List.duplicate(<<0>>, l)

    Enum.reduce(0..(l - 1), result, fn j, acc ->
      orig = Enum.at(c_perm, j)
      List.replace_at(acc, orig, Enum.at(d_syms, j))
    end)
  end
end
