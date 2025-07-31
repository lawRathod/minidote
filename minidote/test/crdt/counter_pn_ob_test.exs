defmodule CounterTest do
  use ExUnit.Case, async: false

  setup_all do
    # Start the server once for all tests in this module
    case Minidote.start_link(Minidote.Server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  test "counter increment and decrement" do
    counter_key = {"user:123", Counter_PN_OB, "page_views"}

    # Initial read should return 0
    {:ok, results, clock1} = Minidote.read_objects([counter_key], 0)
    assert [{^counter_key, 0}] = results

    # Increment by 1
    {:ok, clock2} = Minidote.update_objects([{counter_key, :increment, 1}], clock1)
    assert clock2 > clock1

    # Read should return 1
    {:ok, results, clock3} = Minidote.read_objects([counter_key], clock2)
    assert [{^counter_key, 1}] = results

    # Increment by 5
    {:ok, clock4} = Minidote.update_objects([{counter_key, :increment, 5}], clock3)

    # Read should return 6
    {:ok, results, _clock5} = Minidote.read_objects([counter_key], clock4)
    assert [{^counter_key, 6}] = results

    # Decrement by 2
    {:ok, clock6} = Minidote.update_objects([{counter_key, :decrement, 2}], clock4)

    # Read should return 4
    {:ok, results, _} = Minidote.read_objects([counter_key], clock6)
    assert [{^counter_key, 4}] = results

    # decrement without argument decrements by 1
    {:ok, clock7} = Minidote.update_objects([{counter_key, :decrement}], clock6)

    # Read should return 3 (4 - 1)
    {:ok, results, _} = Minidote.read_objects([counter_key], clock7)
    assert [{^counter_key, 3}] = results
  end

  test "multiple counters" do
    counter1 = {"user:123", Counter_PN_OB, "visits"}
    counter2 = {"user:456", Counter_PN_OB, "clicks"}

    # Update both counters
    updates = [
      {counter1, :increment, 10},
      {counter2, :increment, 5}
    ]

    {:ok, clock} = Minidote.update_objects(updates, 0)

    # Read both counters
    {:ok, results, _} = Minidote.read_objects([counter1, counter2], clock)

    assert Enum.find(results, fn {key, _} -> key == counter1 end) == {counter1, 10}
    assert Enum.find(results, fn {key, _} -> key == counter2 end) == {counter2, 5}
  end
end
