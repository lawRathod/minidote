defmodule MVRegTest do
  use ExUnit.Case, async: false

  setup_all do
    # Start the server once for all tests in this module
    case Minidote.start_link(Minidote.Server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  test "single value assignment" do
    reg_key = {"config", MVReg_OB, "version"}

    # Initial read should return empty list
    {:ok, results, clock1} = Minidote.read_objects([reg_key], 0)
    assert [{^reg_key, values}] = results
    assert values == []

    # Assign a value
    {:ok, clock2} = Minidote.update_objects([{reg_key, :assign, "v1.0"}], clock1)

    # Read should return the single value
    {:ok, results, _} = Minidote.read_objects([reg_key], clock2)
    assert [{^reg_key, values}] = results
    assert values == ["v1.0"]
  end

  test "value overwrites" do
    reg_key = {"user", MVReg_OB, "status"}

    # Assign initial value
    {:ok, clock1} = Minidote.update_objects([{reg_key, :assign, "online"}], 0)

    # Read initial value
    {:ok, results, _} = Minidote.read_objects([reg_key], clock1)
    assert [{^reg_key, ["online"]}] = results

    # Overwrite with new value
    {:ok, clock2} = Minidote.update_objects([{reg_key, :assign, "offline"}], clock1)

    # Should only have the new value
    {:ok, results, _} = Minidote.read_objects([reg_key], clock2)
    assert [{^reg_key, ["offline"]}] = results
  end

  test "sequential assignments overwrite" do
    reg_key = {"doc", MVReg_OB, "content"}

    # Initial assignment
    {:ok, clock1} = Minidote.update_objects([{reg_key, :assign, "version A"}], 0)

    # Sequential assignments (each sees the previous state)
    {:ok, clock2} = Minidote.update_objects([{reg_key, :assign, "version B"}], clock1)
    {:ok, clock3} = Minidote.update_objects([{reg_key, :assign, "version C"}], clock2)

    # Should only have the last value
    {:ok, results, _} = Minidote.read_objects([reg_key], clock3)
    assert [{^reg_key, values}] = results
    assert values == ["version C"]
  end

  test "identical concurrent assignments merge" do
    reg_key = {"setting", MVReg_OB, "theme"}

    # Initial state
    {:ok, clock1} = Minidote.update_objects([{reg_key, :assign, "light"}], 0)

    # Two concurrent assignments of the same value
    {:ok, _clock2} = Minidote.update_objects([{reg_key, :assign, "dark"}], clock1)
    {:ok, _clock3} = Minidote.update_objects([{reg_key, :assign, "dark"}], clock1)

    # Should only have one instance of "dark"
    {:ok, results, _} = Minidote.read_objects([reg_key], 3)
    assert [{^reg_key, values}] = results
    assert values == ["dark"]
  end

  test "causal overwrites" do
    reg_key = {"state", MVReg_OB, "current"}

    # Initial value
    {:ok, clock1} = Minidote.update_objects([{reg_key, :assign, "A"}], 0)

    # Read initial value
    {:ok, results, _} = Minidote.read_objects([reg_key], clock1)
    assert [{^reg_key, ["A"]}] = results

    # New assignment overwrites
    {:ok, clock2} = Minidote.update_objects([{reg_key, :assign, "B"}], clock1)

    # Should only have the new value
    {:ok, results, _} = Minidote.read_objects([reg_key], clock2)
    assert [{^reg_key, ["B"]}] = results
  end
end
