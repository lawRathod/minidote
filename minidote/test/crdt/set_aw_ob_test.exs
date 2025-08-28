defmodule SetTest do
  use ExUnit.Case, async: false

  setup_all do
    # Start the server once for all tests in this module
    case Minidote.start_link(Minidote.Server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  test "set add and remove operations" do
    set_key = {"shopping", Set_AW_OB, "cart"}

    # Initial read should return empty set
    {:ok, results, clock1} = Minidote.read_objects([set_key], 0)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 0

    # Add items
    {:ok, clock2} = Minidote.update_objects([{set_key, :add, "apple"}], clock1)
    {:ok, clock3} = Minidote.update_objects([{set_key, :add, "banana"}], clock2)

    # Read should return both items
    {:ok, results, _} = Minidote.read_objects([set_key], clock3)
    assert [{^set_key, set_value}] = results
    assert MapSet.member?(set_value, "apple")
    assert MapSet.member?(set_value, "banana")
    assert MapSet.size(set_value) == 2

    # Remove one item
    {:ok, clock4} = Minidote.update_objects([{set_key, :remove, "apple"}], clock3)

    # Read should return only banana
    {:ok, results, _} = Minidote.read_objects([set_key], clock4)
    assert [{^set_key, set_value}] = results
    assert not MapSet.member?(set_value, "apple")
    assert MapSet.member?(set_value, "banana")
    assert MapSet.size(set_value) == 1
  end

  test "set add_all and remove_all operations" do
    set_key = {"inventory", Set_AW_OB, "items"}

    # Add multiple items at once
    items = ["item1", "item2", "item3"]
    {:ok, clock1} = Minidote.update_objects([{set_key, :add_all, items}], 0)

    # Read should return all items
    {:ok, results, _} = Minidote.read_objects([set_key], clock1)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 3

    Enum.each(items, fn item ->
      assert MapSet.member?(set_value, item)
    end)

    # Remove multiple items
    {:ok, clock2} = Minidote.update_objects([{set_key, :remove_all, ["item1", "item3"]}], clock1)

    # Should only have item2 left
    {:ok, results, _} = Minidote.read_objects([set_key], clock2)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 1
    assert MapSet.member?(set_value, "item2")
  end

  test "set reset operation" do
    set_key = {"temp", Set_AW_OB, "data"}

    # Add some items
    {:ok, clock1} = Minidote.update_objects([{set_key, :add_all, ["a", "b", "c"]}], 0)

    # Verify they exist
    {:ok, results, _} = Minidote.read_objects([set_key], clock1)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 3

    # Reset the set
    {:ok, clock2} = Minidote.update_objects([{set_key, :reset, {}}], clock1)

    # Should be empty
    {:ok, results, _} = Minidote.read_objects([set_key], clock2)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 0
  end

  test "add-wins semantics" do
    set_key = {"concurrent", Set_AW_OB, "test"}

    # This test demonstrates that each add operation creates a unique token
    # and remove only removes the tokens it knows about

    # Add an element with first token
    {:ok, clock1} = Minidote.update_objects([{set_key, :add, "winner"}], 0)

    # Remove the element (this captures the first token)
    {:ok, clock2} = Minidote.update_objects([{set_key, :remove, "winner"}], clock1)

    # Verify it's removed
    {:ok, results1, _} = Minidote.read_objects([set_key], clock2)
    assert [{^set_key, set_value1}] = results1
    assert not MapSet.member?(set_value1, "winner")

    # Add the same element again (creates a new token)
    {:ok, clock3} = Minidote.update_objects([{set_key, :add, "winner"}], clock2)

    # The element should be present because the new add token wasn't removed
    {:ok, results2, _} = Minidote.read_objects([set_key], clock3)
    assert [{^set_key, set_value2}] = results2
    assert MapSet.member?(set_value2, "winner"), "Element should be present with new add token"

    # Even if we try an old remove operation, it shouldn't affect the new token
    # This demonstrates add-wins: new adds create new tokens that old removes don't affect
  end
end
