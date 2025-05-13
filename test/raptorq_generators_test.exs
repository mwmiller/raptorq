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
end
