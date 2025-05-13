defmodule RaptorqGeneratorsTest do
  use ExUnit.Case
  doctest Raptorq.Generators
  import Raptorq.Generators

  test "rand" do
    assert rand(1, 1, 1) == 0
    assert_raise ArgumentError, fn -> rand(-1, 1, 1) end
    assert_raise ArgumentError, fn -> rand(1, -1, 1) end
    assert_raise ArgumentError, fn -> rand(1, 256, 1) end
    assert_raise ArgumentError, fn -> rand(1, 1, 0) end

    # Despite its name it's not really random
    # just sort of unpredictable at first glance
    assert rand(1, 1, 1024) == 488
    assert rand(1, 255, 1024) == 432
    assert rand(2048, 0, 1024) == 129
    assert rand(2048, 255, 1024) == 529
    assert rand(2048, 0, 1024 ** 10) == 4_190_514_305
    assert rand(2048, 255, 1024 ** 10) == 1_513_049_617
  end

  test "deg" do
    assert_raise ArgumentError, fn -> deg(-1, 1) end
    assert_raise ArgumentError, fn -> deg(1024, 9) end
    assert deg(0, 10) == 0
    assert deg(5242, 10) == 0
    assert deg(5243, 10) == 1
    assert deg(529_531, 10) == 2
    assert deg(1_048_576, 10) == 15
    assert deg(1_048_576, 18) == 27
    assert deg(1_048_576, 18) == 27
    assert deg(1_048_576, 20) == 29
    assert deg(1_048_576, 26) == 30
    assert deg(1_017_662, 26) == 29
    assert deg(1_017_662, 1777) == 29
    assert_raise ArgumentError, fn -> deg(1_017_662, 1_234_567) end
  end

  test "tuple" do
    assert_raise ArgumentError, fn -> tuple(-1, 1) end
    assert_raise ArgumentError, fn -> tuple(9, 10) end
    assert tuple(10, 10) == {1, 15, 15, 2, 10, 7}
    assert tuple(10, 0) == {1, 4, 9, 2, 5, 1}
    assert tuple(18, 10) == {17, 26, 16, 2, 10, 7}
    assert tuple(1777, 10) == {2, 1763, 1006, 2, 66, 55}
  end
end
