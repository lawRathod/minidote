defmodule VcgenserverTest do
  use ExUnit.Case
  doctest Vcgenserver

  test "greets the world" do
    assert Vcgenserver.hello() == :world
  end
end
