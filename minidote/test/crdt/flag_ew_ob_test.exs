defmodule FlagTest do
  use ExUnit.Case, async: false

  setup_all do
    # Start the server once for all tests in this module
    case Minidote.start_link(Minidote.Server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  test "basic enable and disable operations" do
    flag_key = {"feature", Flag_EW_OB, "enabled"}

    # Initial read should return false (disabled)
    {:ok, results, clock1} = Minidote.read_objects([flag_key], 0)
    assert [{^flag_key, false}] = results

    # Enable the flag
    {:ok, clock2} = Minidote.update_objects([{flag_key, :enable}], clock1)

    # Read should return true
    {:ok, results, _} = Minidote.read_objects([flag_key], clock2)
    assert [{^flag_key, true}] = results

    # Disable the flag
    {:ok, clock3} = Minidote.update_objects([{flag_key, :disable}], clock2)

    # Read should return false
    {:ok, results, _} = Minidote.read_objects([flag_key], clock3)
    assert [{^flag_key, false}] = results
  end

  test "enable wins semantics" do
    flag_key = {"concurrent", Flag_EW_OB, "test"}

    # This test demonstrates the enable-wins property
    # Enable after disable should result in enabled state

    # Start with disabled state
    {:ok, results, clock1} = Minidote.read_objects([flag_key], 0)
    assert [{^flag_key, false}] = results

    # Enable the flag
    {:ok, clock2} = Minidote.update_objects([{flag_key, :enable}], clock1)

    # Disable it
    {:ok, clock3} = Minidote.update_objects([{flag_key, :disable}], clock2)

    # Should be disabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock3)
    assert [{^flag_key, false}] = results

    # Enable again after disable - this demonstrates enable-wins
    {:ok, clock4} = Minidote.update_objects([{flag_key, :enable}], clock3)

    # Should be enabled (enable wins)
    {:ok, results, _} = Minidote.read_objects([flag_key], clock4)
    assert [{^flag_key, true}] = results
  end

  test "enable after disable" do
    flag_key = {"sequence", Flag_EW_OB, "test"}

    # Enable, then disable
    {:ok, clock1} = Minidote.update_objects([{flag_key, :enable}], 0)
    {:ok, clock2} = Minidote.update_objects([{flag_key, :disable}], clock1)

    # Should be disabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock2)
    assert [{^flag_key, false}] = results

    # Enable again - should work
    {:ok, clock3} = Minidote.update_objects([{flag_key, :enable}], clock2)

    # Should be enabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock3)
    assert [{^flag_key, true}] = results
  end

  test "multiple enables and disables" do
    flag_key = {"multi", Flag_EW_OB, "ops"}

    # Multiple enables
    {:ok, clock1} = Minidote.update_objects([{flag_key, :enable}], 0)
    {:ok, clock2} = Minidote.update_objects([{flag_key, :enable}], clock1)

    # Should be enabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock2)
    assert [{^flag_key, true}] = results

    # Disable should disable all previous enables
    {:ok, clock3} = Minidote.update_objects([{flag_key, :disable}], clock2)

    # Should be disabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock3)
    assert [{^flag_key, false}] = results

    # New enable after disable should work
    {:ok, clock4} = Minidote.update_objects([{flag_key, :enable}], clock3)

    # Should be enabled again
    {:ok, results, _} = Minidote.read_objects([flag_key], clock4)
    assert [{^flag_key, true}] = results
  end

  test "enable with arguments" do
    flag_key = {"args", Flag_EW_OB, "test"}

    # Enable with argument (should work the same)
    {:ok, clock1} = Minidote.update_objects([{flag_key, :enable, "reason"}], 0)

    # Should be enabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock1)
    assert [{^flag_key, true}] = results

    # Disable with argument
    {:ok, clock2} = Minidote.update_objects([{flag_key, :disable, "maintenance"}], clock1)

    # Should be disabled
    {:ok, results, _} = Minidote.read_objects([flag_key], clock2)
    assert [{^flag_key, false}] = results
  end
end
