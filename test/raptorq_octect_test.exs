defmodule RaptorqOctetTest do
  use ExUnit.Case
  doctest Raptorq.Octet
  alias Raptorq.Octet

  test "add" do
    assert Octet.add(<<0>>, <<0>>) == <<0>>
    assert Octet.add(<<1>>, <<0>>) == <<1>>
    assert Octet.add(<<1>>, <<1>>) == <<0>>
    assert_raise ArgumentError, fn -> Octet.sub(<<1>>, 1) end
  end

  test "sub" do
    assert Octet.sub(<<0>>, <<0>>) == <<0>>
    assert Octet.sub(<<1>>, <<0>>) == <<1>>
    assert Octet.sub(<<1>>, <<1>>) == <<0>>
    assert_raise ArgumentError, fn -> Octet.sub(1, <<1>>) end
  end

  test "mul" do
    assert Octet.mul(<<0>>, <<0>>) == <<0>>
    assert Octet.mul(<<1>>, <<0>>) == <<0>>
    assert Octet.mul(<<255>>, <<1>>) == <<255>>
    assert Octet.mul(<<255>>, <<2>>) == <<227>>
    assert_raise ArgumentError, fn -> Octet.mul(255, <<2>>) end
  end

  test "div" do
    assert Octet.div(<<255>>, <<1>>) == <<255>>
    assert_raise ArgumentError, fn -> Octet.div(<<127>>, <<0>>) end
    assert Octet.div(<<255>>, <<2>>) == <<241>>
    assert_raise ArgumentError, fn -> Octet.div(<<255>>, 2) end
  end
end
