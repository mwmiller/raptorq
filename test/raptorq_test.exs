defmodule RaptorqTest do
  use ExUnit.Case
  doctest Raptorq

  test "greets the world" do
    assert Raptorq.hello() == :world
  end
end
