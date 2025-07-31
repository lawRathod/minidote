defmodule CounterSBTest do
  use ExUnit.Case, async: false

  setup_all do
    # Start the server once for all tests in this module
    case Minidote.start_link(Minidote.Server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  test "state-based counter increment and decrement" do
    counter_key = {"user:456", Counter_PN_SB, "actions"}

    # Initial read should return 0
    {:ok, results, clock1} = Minidote.read_objects([counter_key], 0)
    assert [{^counter_key, 0}] = results

    # Increment by 1
    {:ok, clock2} = Minidote.update_objects([{counter_key, :increment, 1}], clock1)

    # Read should return 1
    {:ok, results, _} = Minidote.read_objects([counter_key], clock2)
    assert [{^counter_key, 1}] = results

    # Increment by 5
    {:ok, clock3} = Minidote.update_objects([{counter_key, :increment, 5}], clock2)

    # Read should return 6
    {:ok, results, _} = Minidote.read_objects([counter_key], clock3)
    assert [{^counter_key, 6}] = results

    # Decrement by 2
    {:ok, clock4} = Minidote.update_objects([{counter_key, :decrement, 2}], clock3)

    # Read should return 4
    {:ok, results, _} = Minidote.read_objects([counter_key], clock4)
    assert [{^counter_key, 4}] = results
  end

  test "state-based counter merge behavior" do
    # Test the merge function directly
    state1 = %{
      positive: %{node() => 10, :node2@host => 5},
      negative: %{node() => 3, :node2@host => 1}
    }

    state2 = %{
      positive: %{node() => 8, :node2@host => 7, :node3@host => 2},
      negative: %{node() => 3, :node2@host => 2}
    }

    merged = Counter_PN_SB.merge(state1, state2)

    # Merge should take maximum values for each node
    # max(10, 8)
    assert merged.positive[node()] == 10
    # max(5, 7)
    assert merged.positive[:node2@host] == 7
    # only in state2
    assert merged.positive[:node3@host] == 2
    # max(3, 3)
    assert merged.negative[node()] == 3
    # max(1, 2)
    assert merged.negative[:node2@host] == 2

    # Value should be sum of positives minus sum of negatives
    assert Counter_PN_SB.value(merged) == 10 + 7 + 2 - (3 + 2)
    assert Counter_PN_SB.value(merged) == 14
  end

  test "state-based counter operations" do
    counter_key = {"metrics", Counter_PN_SB, "requests"}

    # Multiple increments
    {:ok, clock1} = Minidote.update_objects([{counter_key, :increment, 100}], 0)
    {:ok, clock2} = Minidote.update_objects([{counter_key, :increment, 50}], clock1)

    # Multiple decrements
    {:ok, clock3} = Minidote.update_objects([{counter_key, :decrement, 30}], clock2)
    {:ok, clock4} = Minidote.update_objects([{counter_key, :decrement, 20}], clock3)

    # Final value should be 100 + 50 - 30 - 20 = 100
    {:ok, results, _} = Minidote.read_objects([counter_key], clock4)
    assert [{^counter_key, 100}] = results
  end

  test "state-based counter default operations" do
    counter_key = {"default", Counter_PN_SB, "ops"}

    # Increment without value (defaults to 1)
    {:ok, clock1} = Minidote.update_objects([{counter_key, :increment}], 0)
    {:ok, results, _} = Minidote.read_objects([counter_key], clock1)
    assert [{^counter_key, 1}] = results

    # Decrement without value (defaults to 1)
    {:ok, clock2} = Minidote.update_objects([{counter_key, :decrement}], clock1)
    {:ok, results, _} = Minidote.read_objects([counter_key], clock2)
    assert [{^counter_key, 0}] = results
  end
end
