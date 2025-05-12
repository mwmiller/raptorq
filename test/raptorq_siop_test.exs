defmodule RaptorqSIOPTest do
  use ExUnit.Case
  doctest Raptorq.SIOP
  import Raptorq.SIOP

  test "j" do
    assert_raise ArgumentError, fn -> j(9) end
    assert j(10) == 254
    assert j(217) == 764
    assert j(549) == 497
    assert j(1777) == 860
    assert j(7855) == 332
    assert j(23491) == 121
    assert j(48007) == 269
    assert j(56403) == 471
    assert_raise ArgumentError, fn -> j(56404) end
  end

  test "s" do
    assert_raise ArgumentError, fn -> s(9) end
    assert s(10) == 7
    assert s(217) == 29
    assert s(549) == 41
    assert s(1777) == 79
    assert s(7855) == 211
    assert s(23491) == 457
    assert s(48007) == 787
    assert s(56403) == 907
    assert_raise ArgumentError, fn -> s(56404) end
  end

  test "h" do
    assert_raise ArgumentError, fn -> h(9) end
    assert h(10) == 10
    assert h(217) == 10
    assert h(549) == 10
    assert h(1777) == 11
    assert h(7855) == 11
    assert h(23491) == 13
    assert h(48007) == 15
    assert h(56403) == 16
    assert_raise ArgumentError, fn -> h(56404) end
  end

  test "w" do
    assert_raise ArgumentError, fn -> w(9) end
    assert w(10) == 17
    assert w(217) == 233
    assert w(549) == 563
    assert w(1777) == 1801
    assert w(7855) == 7937
    assert w(23491) == 23719
    assert w(48007) == 48463
    assert w(56403) == 56951
    assert_raise ArgumentError, fn -> w(56404) end
  end
end
