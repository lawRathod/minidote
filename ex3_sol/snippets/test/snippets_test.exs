defmodule SnippetsTest do
  use ExUnit.Case
  doctest Snippets

  test "greets the world" do
    assert Snippets.hello() == :world
  end
end
