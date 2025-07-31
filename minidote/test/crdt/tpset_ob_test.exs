defmodule TPSetTest do
  use ExUnit.Case, async: false

  setup_all do
    # Start the server once for all tests in this module
    case Minidote.start_link(Minidote.Server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  test "basic add and remove" do
    set_key = {"tasks", TPSet_OB, "todo"}

    # Initial read should return empty set
    {:ok, results, clock1} = Minidote.read_objects([set_key], 0)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 0

    # Add items
    {:ok, clock2} = Minidote.update_objects([{set_key, :add, "task1"}], clock1)
    {:ok, clock3} = Minidote.update_objects([{set_key, :add, "task2"}], clock2)

    # Read should return both items
    {:ok, results, _} = Minidote.read_objects([set_key], clock3)
    assert [{^set_key, set_value}] = results
    assert MapSet.member?(set_value, "task1")
    assert MapSet.member?(set_value, "task2")

    # Remove one item
    {:ok, clock4} = Minidote.update_objects([{set_key, :remove, "task1"}], clock3)

    # Should only have task2
    {:ok, results, _} = Minidote.read_objects([set_key], clock4)
    assert [{^set_key, set_value}] = results
    assert not MapSet.member?(set_value, "task1")
    assert MapSet.member?(set_value, "task2")
  end

  test "cannot re-add removed element" do
    set_key = {"users", TPSet_OB, "banned"}

    # Add a user
    {:ok, clock1} = Minidote.update_objects([{set_key, :add, "user123"}], 0)

    # Remove the user
    {:ok, clock2} = Minidote.update_objects([{set_key, :remove, "user123"}], clock1)

    # Try to re-add - should fail
    {:error, _reason} = Minidote.update_objects([{set_key, :add, "user123"}], clock2)

    # Verify user is still removed
    {:ok, results, _} = Minidote.read_objects([set_key], clock2)
    assert [{^set_key, set_value}] = results
    assert not MapSet.member?(set_value, "user123")
  end

  test "cannot remove non-existent element" do
    set_key = {"items", TPSet_OB, "inventory"}

    # Try to remove element that was never added
    {:error, _reason} = Minidote.update_objects([{set_key, :remove, "nonexistent"}], 0)
  end

  test "add_all and remove_all operations" do
    set_key = {"batch", TPSet_OB, "items"}

    # Add multiple items
    items = ["item1", "item2", "item3", "item4"]
    {:ok, clock1} = Minidote.update_objects([{set_key, :add_all, items}], 0)

    # Verify all added
    {:ok, results, _} = Minidote.read_objects([set_key], clock1)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 4

    Enum.each(items, fn item ->
      assert MapSet.member?(set_value, item)
    end)

    # Remove multiple items
    {:ok, clock2} = Minidote.update_objects([{set_key, :remove_all, ["item1", "item3"]}], clock1)

    # Should have item2 and item4
    {:ok, results, _} = Minidote.read_objects([set_key], clock2)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 2
    assert MapSet.member?(set_value, "item2")
    assert MapSet.member?(set_value, "item4")
  end

  test "add_all filters out tombstoned elements" do
    set_key = {"filtered", TPSet_OB, "set"}

    # Add and remove an element
    {:ok, clock1} = Minidote.update_objects([{set_key, :add, "removed"}], 0)
    {:ok, clock2} = Minidote.update_objects([{set_key, :remove, "removed"}], clock1)

    # Try to add multiple including the removed one
    {:ok, clock3} =
      Minidote.update_objects([{set_key, :add_all, ["new1", "removed", "new2"]}], clock2)

    # Should only have the non-tombstoned elements
    {:ok, results, _} = Minidote.read_objects([set_key], clock3)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 2
    assert MapSet.member?(set_value, "new1")
    assert MapSet.member?(set_value, "new2")
    assert not MapSet.member?(set_value, "removed")
  end

  test "remove_all only removes existing elements" do
    set_key = {"selective", TPSet_OB, "removal"}

    # Add some elements
    {:ok, clock1} = Minidote.update_objects([{set_key, :add_all, ["a", "b", "c"]}], 0)

    # Try to remove mix of existing and non-existing
    {:ok, clock2} =
      Minidote.update_objects([{set_key, :remove_all, ["a", "nonexist", "c", "other"]}], clock1)

    # Should only have b left
    {:ok, results, _} = Minidote.read_objects([set_key], clock2)
    assert [{^set_key, set_value}] = results
    assert MapSet.size(set_value) == 1
    assert MapSet.member?(set_value, "b")
  end
end
