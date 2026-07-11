defmodule Raptorq.Solver5 do
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

  defstruct A: [], D: [], c: [], d: [], i: 0, u: 0, L: 0, M: 0,
            params: %{}

  @doc """
  Solve A·C = D using the 5-phase algorithm.
  """
  def solve(constraint_rows, params, d_symbols) do
    %{l: l, p: p} = params
    m = length(constraint_rows)

    a = Enum.map(constraint_rows, fn row -> Map.new(row) end)

    solver = %__MODULE__{
      A: a, D: d_symbols,
      c: Enum.to_list(0..(l - 1)),
      d: Enum.to_list(0..(m - 1)),
      i: 0, u: p, L: l, M: m,
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
    candidates = Enum.filter(non_hdpc, fn row ->
      has_v(a, row, i, v_end)
    end)

    candidates = if candidates == [] do
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

      {a, d} =
        if pivot_val != <<0>> do
          (i + 1)..(m - 1)
          |> Enum.reduce({a2, d2}, fn row, {a_acc, d_acc} ->
            row_map = Enum.at(a_acc, row, %{})
            beta = Map.get(row_map, i, <<0>>)
            if beta == <<0>> do
              {a_acc, d_acc}
            else
              scalar = Octet.odiv(beta, pivot_val)
              a_acc = fma(a_acc, i, row, scalar)
              d_acc = Octet.sadd(Enum.at(d_acc, row), Octet.smul(Enum.at(d_acc, i), scalar))
                         |> then(fn v -> List.replace_at(d_acc, row, v) end)
              {a_acc, d_acc}
            end
          end)
        else
          {a2, d2}
        end

      solver = %{solver | A: a, D: d}
      solver = %{solver | i: i + 1, u: u + r - 1}

      first_phase(solver)
    end
  end

  # ── Row selection heuristics ──────────────────────────────────────────

  defp select_row(a, candidates, r, v_start, v_end) do
    if r == 2 do
      rows_with_2 = Enum.filter(candidates, fn row ->
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
    edges = Enum.flat_map(rows, fn row ->
      row_map = Enum.at(a, row, %{})
      ones = row_map
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
      adj = Enum.reduce(edges, %{}, fn {a, b}, acc ->
        acc |> Map.update(a, [b], fn es -> [b | es] end)
            |> Map.update(b, [a], fn es -> [a | es] end)
      end)
      visited = MapSet.new()
      components = find_components(nodes, adj, visited, [])

      largest = Enum.max_by(components, &length/1)
      pivot_col = hd(largest)
      Enum.find(rows, fn row -> Map.get(Enum.at(a, row, %{}), pivot_col, <<0>>) != <<0>> end)
      || hd(rows)
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
    %{solver | A: swap_list(a, pos, chosen),
               D: swap_list(d, pos, chosen),
               d: swap_list(d_perm, pos, chosen)}
  end

  defp arrange_columns(solver, pivot_row, _r) do
    %{A: a, i: i, u: u, L: l} = solver
    v_end = l - u
    row_map = Enum.at(a, pivot_row, %{})

    nz_cols = row_map
    |> Enum.filter(fn {col, val} ->
      col >= i and col < v_end and val != <<0>>
    end)
    |> Enum.map(fn {col, _} -> col end)
    |> Enum.sort()

    case nz_cols do
      [] -> solver
      [first | rest] ->
        # Swap first non-zero V column to position i (I column)
        solver = if first != i, do: swap_columns(solver, first, i), else: solver

        # Move remaining non-zero V columns to U positions
        Enum.reduce(Enum.with_index(rest), solver, fn {col, idx}, s ->
          dest = v_end - 1 - idx
          if col != dest, do: swap_columns(s, col, dest), else: s
        end)
    end
  end

  defp swap_columns(solver, col1, col2) do
    %{A: a, c: c_perm} = solver
    new_a = Enum.map(a, fn row_map ->
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

    merged = Map.merge(scaled_src, dest_row, fn _col, v_prod, v_dest ->
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
    s = %__MODULE__{A: a, D: d_syms, c: Enum.to_list(0..(l-1)), d: Enum.to_list(0..(m-1)),
                    i: 0, u: p, L: l, M: m, params: params}
    case first_phase(s) do
      {:ok, s1} ->
        case second_phase(s1) do
          {:ok, s2} ->
            s3 = third_phase(s2)
            s5p = fifth_phase(s3)
            s4 = fourth_phase(s5p)
            {:ok, s1, s2, s3, s4, s5p}
          err -> err
        end
      err -> err
    end
  end

  # ── Phase 2 — §5.4.2.3 ────────────────────────────────────────────────

  defp second_phase(%{u: u} = solver) when u == 0, do: {:ok, truncate_matrix(solver)}

  defp second_phase(solver) do
    %{i: i, u: u, L: l, M: m, A: a, D: d, d: d_perm} = solver
    u_start = l - u

    # Extract U-lower rows (positions i..M-1)
    u_lower_pos = Enum.to_list(i..(m - 1))
    u_lower = Enum.map(u_lower_pos, fn pos ->
      row_map = Enum.at(a, pos, %{})
      for col <- u_start..(l - 1), do: Map.get(row_map, col, <<0>>)
    end)

    # Dense GE on U matrix (track ops, apply to A and D)
    {_, final_a, final_d, final_d_perm} =
      Enum.reduce(0..(u - 1), {u_lower, a, d, d_perm}, fn col, {r_a, a_a, d_a, dp_a} ->
        pivot_idx = Enum.find_index(Enum.drop(r_a, col), fn r -> Enum.at(r, col) != <<0>> end)
        if pivot_idx == nil, do: throw({:singular, col})

        pivot_actual = col + pivot_idx
        src_pos = Enum.at(u_lower_pos, col)
        src_pivot_pos = Enum.at(u_lower_pos, pivot_actual)

        # Swap in U rows and in A/D
        {r_a, a_a, d_a, dp_a} =
          if pivot_actual != col do
            {swap_list(r_a, col, pivot_actual),
             swap_list(a_a, src_pos, src_pivot_pos),
             swap_list(d_a, src_pos, src_pivot_pos),
             swap_list(dp_a, src_pos, src_pivot_pos)}
          else
            {r_a, a_a, d_a, dp_a}
          end

        pivot_val = r_a |> Enum.at(col) |> Enum.at(col)

        # Scale pivot row
        {r_a, a_a, d_a} =
          if pivot_val != <<1>> do
            inv = Octet.odiv(<<1>>, pivot_val)
            r_a = List.update_at(r_a, col, fn r -> Enum.map(r, &Octet.omul(&1, inv)) end)
            a_a = scale_sparse(a_a, src_pos, inv)
            d_a = List.update_at(d_a, src_pos, &Octet.smul(&1, inv))
            {r_a, a_a, d_a}
          else
            {r_a, a_a, d_a}
          end

        pivot_row = Enum.at(r_a, col)

        # Eliminate column from all OTHER U rows
        {r_a, a_a, d_a} =
          Enum.reduce(Enum.reject(0..(u - 1), &(&1 == col)), {r_a, a_a, d_a},
            fn r, {r2_a, a2_a, d2_a} ->
              val = r2_a |> Enum.at(r) |> Enum.at(col)
              if val != <<0>> do
                new_r = Enum.zip_with(Enum.at(r2_a, r), pivot_row, fn v, pv ->
                  Octet.oadd(v, Octet.omul(pv, val))
                end)
                src_row = Enum.at(u_lower_pos, col)
                dest_row = Enum.at(u_lower_pos, r)
                {List.replace_at(r2_a, r, new_r),
                 fma(a2_a, src_row, dest_row, val),
                 List.update_at(d2_a, dest_row, &Octet.sadd(&1, Octet.smul(Enum.at(d2_a, src_row), val)))}
              else
                {r2_a, a2_a, d2_a}
              end
            end)

        {r_a, a_a, d_a, dp_a}
      end)

    # Write identity in U portion of A for the processed rows
    a2 = Enum.reduce(0..(u - 1), final_a, fn offset, a_acc ->
      act_row = Enum.at(u_lower_pos, offset)
      row_map = Enum.at(a_acc, act_row, %{})
      new_row =
        Enum.reduce(0..(u - 1), row_map, fn col_off, r ->
          c = u_start + col_off
          if offset == col_off do
            Map.put(r, c, <<1>>)
          else
            Map.delete(r, c)
          end
        end)
      List.replace_at(a_acc, act_row, new_row)
    end)

    {:ok, truncate_matrix(%{solver | A: a2, D: final_d, d: final_d_perm})}
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
    %{i: i, u: u, L: l} = solver
    u_start = l - u

    # Eliminate U columns from rows 0..i-1 using U-identity rows
    for row <- 0..(i - 1), reduce: solver do
      s ->
        row_map = Enum.at(Map.get(s, :A), row, %{})
        u_nz = Enum.filter(row_map, fn {col, val} ->
          col >= u_start and val != <<0>>
        end)

        Enum.reduce(u_nz, s, fn {col, val}, s2 ->
          a2 = fma(Map.get(s2, :A), col, row, val)
          d2 = List.update_at(Map.get(s2, :D), row, &Octet.sadd(&1, Octet.smul(Enum.at(Map.get(s2, :D), col), val)))
          %{s2 | A: a2, D: d2}
        end)
    end
  end

  # ── Phase 4 — §5.4.2.5 ────────────────────────────────────────────────

  defp fourth_phase(solver) do
    %{i: i, M: m, L: l, u: u} = solver
    u_start = l - u

    for row <- i..(m - 1), reduce: solver do
      s ->
        row_map = Enum.at(Map.get(s, :A), row, %{})
        u_nz = Enum.filter(row_map, fn {col, val} ->
          col >= u_start and val != <<0>> and col != row
        end)

        s = Enum.reduce(u_nz, s, fn {col, val}, s2 ->
          a2 = fma(Map.get(s2, :A), col, row, val)
          d2 = List.update_at(Map.get(s2, :D), row, &Octet.sadd(&1, Octet.smul(Enum.at(Map.get(s2, :D), col), val)))
          %{s2 | A: a2, D: d2}
        end)

        row_map = Enum.at(Map.get(s, :A), row, %{})
        i_nz = Enum.filter(row_map, fn {col, _val} ->
          col < i
        end)

        Enum.reduce(i_nz, s, fn {col, _}, s2 ->
          a = Map.get(s2, :A)
          curr_row = Enum.at(a, row, %{})
          val = Map.get(curr_row, col, <<0>>)

          if val != <<0>> do
            pivot_val = Map.get(Enum.at(a, col, %{}), col, <<1>>)
            sc = Octet.odiv(val, pivot_val)
            a2 = fma(a, col, row, sc)
            d2 = List.update_at(Map.get(s2, :D), row, &Octet.sadd(&1, Octet.smul(Enum.at(Map.get(s2, :D), col), sc)))
            %{s2 | A: a2, D: d2}
          else
            s2
          end
        end)
    end
  end

  # ── Phase 5 — Full Gauss-Jordan on I×I submatrix ──────────────────

  defp fifth_phase(solver) do
    %{i: i} = solver
    for pivot <- 0..(i - 1), reduce: solver do
      s ->
        %{A: a, D: d} = s

        # 1. Scale pivot to 1
        diag = Map.get(Enum.at(a, pivot, %{}), pivot, <<0>>)
        s = if diag != <<1>> and diag != <<0>> do
          inv = Octet.odiv(<<1>>, diag)
          %{s | A: scale_sparse(a, pivot, inv),
                D: List.update_at(d, pivot, &Octet.smul(&1, inv))}
        else
          s
        end

        # 2. Eliminate pivot column from ALL other I rows
        for r <- 0..(i - 1), r != pivot, reduce: s do
          s2 ->
            %{A: a2, D: d2} = s2
            beta = Map.get(Enum.at(a2, r, %{}), pivot, <<0>>)
            if beta != <<0>> do
              %{s2 | A: fma(a2, pivot, r, beta),
                     D: List.update_at(d2, r, &Octet.sadd(&1, Octet.smul(Enum.at(d2, pivot), beta)))}
            else
              s2
            end
        end
    end
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

