defmodule VectorClockTest do
  use ExUnit.Case
  alias VectorClock

  test "new vector clock is empty" do
    clock = VectorClock.new()
    assert clock == %{}
    assert VectorClock.nodes(clock) == []
  end

  test "new vector clock with node initializes correctly" do
    node = :test_node
    clock = VectorClock.new(node)
    assert clock == %{test_node: 0}
    assert VectorClock.get(clock, node) == 0
  end

  test "increment advances clock for specific node" do
    clock = VectorClock.new()

    clock1 = VectorClock.increment(clock, :node1)
    assert VectorClock.get(clock1, :node1) == 1
    assert VectorClock.get(clock1, :node2) == 0

    clock2 = VectorClock.increment(clock1, :node1)
    assert VectorClock.get(clock2, :node1) == 2

    clock3 = VectorClock.increment(clock2, :node2)
    assert VectorClock.get(clock3, :node1) == 2
    assert VectorClock.get(clock3, :node2) == 1
  end

  test "merge takes maximum of each node" do
    clock1 = %{node1: 3, node2: 1, node3: 5}
    clock2 = %{node1: 2, node2: 4, node4: 2}

    merged = VectorClock.merge(clock1, clock2)

    # max(3, 2)
    assert VectorClock.get(merged, :node1) == 3
    # max(1, 4)
    assert VectorClock.get(merged, :node2) == 4
    # max(5, 0)
    assert VectorClock.get(merged, :node3) == 5
    # max(0, 2)
    assert VectorClock.get(merged, :node4) == 2
  end

  test "compare detects equal clocks" do
    clock1 = %{node1: 2, node2: 3}
    clock2 = %{node1: 2, node2: 3}

    assert VectorClock.compare(clock1, clock2) == :equal
  end

  test "compare detects before relationship" do
    clock1 = %{node1: 1, node2: 2}
    clock2 = %{node1: 2, node2: 3}

    assert VectorClock.compare(clock1, clock2) == :before
    assert VectorClock.before?(clock1, clock2) == true
    assert VectorClock.after?(clock1, clock2) == false
  end

  test "compare detects after relationship" do
    clock1 = %{node1: 3, node2: 4}
    clock2 = %{node1: 2, node2: 3}

    assert VectorClock.compare(clock1, clock2) == :after
    assert VectorClock.before?(clock1, clock2) == false
    assert VectorClock.after?(clock1, clock2) == true
  end

  test "compare detects concurrent relationship" do
    clock1 = %{node1: 2, node2: 1}
    clock2 = %{node1: 1, node2: 2}

    assert VectorClock.compare(clock1, clock2) == :concurrent
    assert VectorClock.concurrent?(clock1, clock2) == true
    assert VectorClock.before?(clock1, clock2) == false
    assert VectorClock.after?(clock1, clock2) == false
  end

  test "compare handles missing nodes correctly" do
    clock1 = %{node1: 2}
    clock2 = %{node2: 1}

    # Both have advances the other hasn't seen - concurrent
    assert VectorClock.compare(clock1, clock2) == :concurrent
  end

  test "compare with empty clocks" do
    empty = VectorClock.new()
    clock = %{node1: 1}

    assert VectorClock.compare(empty, clock) == :before
    assert VectorClock.compare(clock, empty) == :after
    assert VectorClock.compare(empty, empty) == :equal
  end

  test "put and get operations" do
    clock = VectorClock.new()

    clock1 = VectorClock.put(clock, :node1, 5)
    assert VectorClock.get(clock1, :node1) == 5

    clock2 = VectorClock.put(clock1, :node1, 10)
    assert VectorClock.get(clock2, :node1) == 10
  end

  test "nodes returns all participating nodes" do
    clock = %{node1: 2, node2: 0, node3: 5}
    nodes = VectorClock.nodes(clock)

    assert Enum.sort(nodes) == [:node1, :node2, :node3]
  end

  test "to_string formats clock readably" do
    clock = %{node1: 2, node2: 0}
    string_repr = VectorClock.to_string(clock)

    # Should contain both nodes and their values
    assert string_repr =~ "node1:2"
    assert string_repr =~ "node2:0"
    assert String.starts_with?(string_repr, "{")
    assert String.ends_with?(string_repr, "}")
  end

  test "complex causal scenario" do
    # Simulate a realistic distributed scenario

    # Initial state - all nodes start with empty clocks
    clock_a = VectorClock.new()
    clock_b = VectorClock.new()
    clock_c = VectorClock.new()

    # Node A performs operation
    clock_a1 = VectorClock.increment(clock_a, :node_a)

    # Node A's update reaches Node B
    clock_b1 = VectorClock.merge(clock_b, clock_a1)

    # Node B performs operation
    clock_b2 = VectorClock.increment(clock_b1, :node_b)

    # Node C gets both A and B's updates
    clock_c1 = VectorClock.merge(clock_c, clock_a1)
    clock_c2 = VectorClock.merge(clock_c1, clock_b2)

    # Node C performs operation
    clock_c3 = VectorClock.increment(clock_c2, :node_c)

    # Verify causal relationships
    # A -> B
    assert VectorClock.before?(clock_a1, clock_b2)
    # B -> C
    assert VectorClock.before?(clock_b2, clock_c3)
    # A -> C (transitivity)
    assert VectorClock.before?(clock_a1, clock_c3)

    # Verify final state includes all operations
    assert VectorClock.get(clock_c3, :node_a) == 1
    assert VectorClock.get(clock_c3, :node_b) == 1
    assert VectorClock.get(clock_c3, :node_c) == 1
  end

  test "increment on non-existent node initializes correctly" do
    clock = VectorClock.new()

    clock1 = VectorClock.increment(clock, :new_node)
    assert VectorClock.get(clock1, :new_node) == 1

    clock2 = VectorClock.increment(clock1, :new_node)
    assert VectorClock.get(clock2, :new_node) == 2
  end
end
