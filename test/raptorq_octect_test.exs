defmodule RaptorqOctetTest do
  use ExUnit.Case
  doctest Raptorq.Octet
  import Raptorq.Octet

  test "oadd" do
    assert oadd(<<0>>, <<0>>) == <<0>>
    assert oadd(<<1>>, <<0>>) == <<1>>
    assert oadd(<<1>>, <<1>>) == <<0>>
    assert_raise ArgumentError, fn -> osub(<<1>>, 1) end
  end

  test "osub" do
    assert osub(<<0>>, <<0>>) == <<0>>
    assert osub(<<1>>, <<0>>) == <<1>>
    assert osub(<<1>>, <<1>>) == <<0>>
    assert_raise ArgumentError, fn -> osub(1, <<1>>) end
  end

  test "omul" do
    assert omul(<<0>>, <<0>>) == <<0>>
    assert omul(<<1>>, <<0>>) == <<0>>
    assert omul(<<255>>, <<1>>) == <<255>>
    assert omul(<<255>>, <<2>>) == <<227>>
    assert_raise ArgumentError, fn -> omul(255, <<2>>) end
  end

  test "odiv" do
    assert odiv(<<255>>, <<1>>) == <<255>>
    assert_raise ArgumentError, fn -> odiv(<<127>>, <<0>>) end
    assert odiv(<<255>>, <<2>>) == <<241>>
    assert_raise ArgumentError, fn -> odiv(<<255>>, 2) end
  end

  test "olog" do
    assert_raise ArgumentError, fn -> olog(0) end
    assert_raise ArgumentError, fn -> olog(<<0>>) end
    assert olog(<<1>>) == 0
    assert olog(<<127>>) == 87
    assert olog(<<255>>) == 175
    assert_raise ArgumentError, fn -> olog(<<256>>) end
    assert_raise ArgumentError, fn -> olog(:five) end
  end

  test "oexp" do
    assert_raise ArgumentError, fn -> oexp(-1) end
    assert oexp(0) == <<1>>
    assert oexp(254) == <<142>>
    assert oexp(509) == <<142>>
    assert_raise ArgumentError, fn -> oexp(510) end
    assert_raise ArgumentError, fn -> oexp("1") end
    assert_raise ArgumentError, fn -> oexp(:five) end
  end
end
