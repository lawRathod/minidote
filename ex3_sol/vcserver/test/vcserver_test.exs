defmodule VcserverTest do
  use ExUnit.Case
  doctest Vcserver

  test "greets the world" do
    assert Vcserver.hello() == :world
  end
end
