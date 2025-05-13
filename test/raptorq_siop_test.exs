defmodule RaptorqSIOPTest do
  use ExUnit.Case
  doctest Raptorq.SIOP
  import Raptorq.SIOP

  test "values_for" do
    assert values_for(9, :close) == %{k: 10, j: 254, s: 7, h: 10, w: 17}
    assert values_for(10, :exact) == %{k: 10, j: 254, s: 7, h: 10, w: 17}
    assert values_for(10, :close) == %{k: 10, j: 254, s: 7, h: 10, w: 17}
    assert values_for(217) == %{k: 217, j: 764, s: 29, h: 10, w: 233}
    assert values_for(214, :close) == %{k: 217, j: 764, s: 29, h: 10, w: 233}
    assert values_for(549) == %{k: 549, j: 497, s: 41, h: 10, w: 563}
    assert values_for(1777) == %{k: 1777, j: 860, s: 79, h: 11, w: 1801}
    assert values_for(7855) == %{k: 7855, j: 332, s: 211, h: 11, w: 7937}
    assert values_for(23491) == %{k: 23491, j: 121, s: 457, h: 13, w: 23719}
    assert values_for(48007) == %{k: 48007, j: 269, s: 787, h: 15, w: 48463}
    assert values_for(56402, :close) == %{k: 56403, j: 471, s: 907, h: 16, w: 56951}
    assert values_for(56403) == %{k: 56403, j: 471, s: 907, h: 16, w: 56951}

    assert_raise ArgumentError, fn -> values_for(56404) end
    assert_raise ArgumentError, fn -> values_for(56404, :close) end
    assert_raise ArgumentError, fn -> values_for(9, :exact) end
  end
end
