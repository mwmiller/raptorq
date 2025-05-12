defmodule RaptorqLookupTest do
  use ExUnit.Case
  # This seems pretty unlikely to help but whatever
  doctest Raptorq.Lookup
  import Raptorq.Lookup

  test "v0" do
    assert_raise ArgumentError, fn -> v0(-1) end
    assert v0(0) == 251_291_136
    assert v0(127) == 4_291_353_919
    assert v0(255) == 1_358_307_511
    assert_raise ArgumentError, fn -> v0(256) end
    assert_raise ArgumentError, fn -> v0("1") end
    assert_raise ArgumentError, fn -> v0(:five) end
  end

  test "v1" do
    assert_raise ArgumentError, fn -> v1(-1) end
    assert v1(0) == 807_385_413
    assert v1(127) == 3_870_972_145
    assert v1(255) == 4_135_048_896
    assert_raise ArgumentError, fn -> v1(256) end
    assert_raise ArgumentError, fn -> v1("1") end
    assert_raise ArgumentError, fn -> v1(:five) end
  end

  test "v2" do
    assert_raise ArgumentError, fn -> v2(-1) end
    assert v2(0) == 1_629_829_892
    assert v2(127) == 498_179_069
    assert v2(255) == 3_497_665_928
    assert_raise ArgumentError, fn -> v2(256) end
    assert_raise ArgumentError, fn -> v2("1") end
    assert_raise ArgumentError, fn -> v2(:five) end
  end

  test "v3" do
    assert_raise ArgumentError, fn -> v3(-1) end
    assert v3(0) == 1_191_369_816
    assert v3(127) == 2_923_692_473
    assert v3(255) == 3_432_275_192
    assert_raise ArgumentError, fn -> v3(256) end
    assert_raise ArgumentError, fn -> v3("1") end
    assert_raise ArgumentError, fn -> v3(:five) end
  end
end
