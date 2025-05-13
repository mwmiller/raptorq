defmodule RaptorqSIOPTest do
  use ExUnit.Case
  doctest Raptorq.SIOP
  import Raptorq.SIOP

  test "values_for" do
    k_10 = %{h: 10, j: 254, k: 10, s: 7, w: 17, b: 10, l: 27, p: 10, p1: 11, u: 0}

    assert values_for(9, :close) == k_10
    assert values_for(10, :exact) == k_10
    assert values_for(10, :close) == k_10

    k_217 = %{h: 10, j: 764, k: 217, s: 29, w: 233, b: 204, l: 256, p: 23, p1: 23, u: 13}

    assert values_for(217) == k_217
    assert values_for(214, :close) == k_217

    k_56044 = %{
      h: 16,
      j: 471,
      k: 56403,
      s: 907,
      w: 56951,
      b: 56044,
      l: 57326,
      p: 375,
      p1: 379,
      u: 359
    }

    assert values_for(56402, :close) == k_56044
    assert values_for(56403) == k_56044

    assert_raise ArgumentError, fn -> values_for(56404) end
    assert_raise ArgumentError, fn -> values_for(56404, :close) end
    assert_raise ArgumentError, fn -> values_for(9, :exact) end
  end
end
