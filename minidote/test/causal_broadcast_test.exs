defmodule CausalBroadcastTest do
  use ExUnit.Case
  alias VectorClock

  @moduletag :distributed

  test "causal broadcast maintains causal order" do
    # Test that operations maintain causal ordering across nodes
    # Operation A -> Operation B should be delivered in that order on all nodes

    # Start three nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:cb_node1, :cb_node2, :cb_node3])
    [node1, node2, node3] = nodes

    # Wait for LinkLayer discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    counter_key = {"causal", Counter_PN_OB, "test"}

    # Node1: Initial operation (A)
    {:ok, clock_a} =
      :rpc.call(node1, Minidote, :update_objects, [[{counter_key, :increment, 10}], 0])

    # Node1: Causally dependent operation (B) - depends on A
    {:ok, _clock_b} =
      :rpc.call(node1, Minidote, :update_objects, [[{counter_key, :increment, 5}], clock_a])

    # Allow time for replication
    Process.sleep(200)

    # All nodes should see the same final state (15) 
    # This verifies causal ordering was preserved
    {:ok, results1, _} =
      :rpc.call(node1, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    {:ok, results2, _} =
      :rpc.call(node2, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    {:ok, results3, _} =
      :rpc.call(node3, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    [{^counter_key, value1}] = results1
    [{^counter_key, value2}] = results2
    [{^counter_key, value3}] = results3

    # All nodes should have the same final value
    assert value1 == 15
    assert value2 == 15
    assert value3 == 15

    # Clean up
    TestSetup.stop_nodes(nodes)
  end

  test "vector clocks track causality correctly" do
    # Test that vector clocks properly track causal relationships

    # Start two nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:vc_node1, :vc_node2])
    [node1, node2] = nodes

    # Wait for LinkLayer discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    set_key = {"vector", Set_AW_OB, "items"}

    # Node1: Add item A
    {:ok, clock1} =
      :rpc.call(node1, Minidote, :update_objects, [[{set_key, :add, "item_a"}], VectorClock.new()])

    # Verify clock1 has node1's timestamp incremented
    assert VectorClock.get(clock1, :"vc_node1@127.0.0.1") > 0

    # Allow replication to node2
    Process.sleep(100)

    # Node2: Add item B (should see node1's update in its clock)
    {:ok, clock2} =
      :rpc.call(node2, Minidote, :update_objects, [[{set_key, :add, "item_b"}], VectorClock.new()])

    # Clock2 should reflect both nodes' operations
    assert VectorClock.get(clock2, :"vc_node1@127.0.0.1") > 0
    assert VectorClock.get(clock2, :"vc_node2@127.0.0.1") > 0

    # Final state should have both items
    {:ok, results, final_clock} =
      :rpc.call(node1, Minidote, :read_objects, [[set_key], VectorClock.new()])

    [{^set_key, items}] = results

    sorted_items = Enum.sort(items)
    assert sorted_items == ["item_a", "item_b"]

    # Final clock should show both nodes participated
    assert VectorClock.get(final_clock, :"vc_node1@127.0.0.1") > 0
    assert VectorClock.get(final_clock, :"vc_node2@127.0.0.1") > 0

    # Clean up
    TestSetup.stop_nodes(nodes)
  end

  test "session guarantees with read-your-writes" do
    # Test that a client can read its own writes (session guarantee)

    # Start two nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:ryw_node1, :ryw_node2])
    [node1, node2] = nodes

    # Wait for LinkLayer discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    reg_key = {"session", MVReg_OB, "value"}

    # Client writes to node1
    {:ok, write_clock} =
      :rpc.call(node1, Minidote, :update_objects, [
        [{reg_key, :assign, "my_value"}],
        VectorClock.new()
      ])

    # Client immediately reads from node2 using the write clock
    # This should see the write (session guarantee)
    {:ok, results, _} = :rpc.call(node2, Minidote, :read_objects, [[reg_key], write_clock])
    [{^reg_key, values}] = results

    # Should see the written value
    assert "my_value" in values

    # Clean up
    TestSetup.stop_nodes(nodes)
  end

  test "concurrent operations create correct vector clock ordering" do
    # Test that truly concurrent operations have concurrent vector clocks

    # Start two nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:conc_node1, :conc_node2])
    [node1, node2] = nodes

    # Wait for LinkLayer discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    flag_key = {"concurrent", Flag_EW_OB, "feature"}

    # Both nodes perform operations while disconnected (truly concurrent)
    task1 =
      Task.async(fn ->
        :rpc.call(node1, Minidote, :update_objects, [[{flag_key, :enable}], VectorClock.new()])
      end)

    task2 =
      Task.async(fn ->
        :rpc.call(node2, Minidote, :update_objects, [[{flag_key, :enable}], VectorClock.new()])
      end)

    {:ok, clock1} = Task.await(task1)
    {:ok, clock2} = Task.await(task2)

    # These clocks should be concurrent (neither happens-before the other)
    assert VectorClock.concurrent?(clock1, clock2)

    # Allow additional time for effect synchronization
    Process.sleep(200)

    # Both nodes should converge to the same state
    {:ok, results1, final_clock1} =
      :rpc.call(node1, Minidote, :read_objects, [[flag_key], VectorClock.new()])

    {:ok, results2, final_clock2} =
      :rpc.call(node2, Minidote, :read_objects, [[flag_key], VectorClock.new()])

    [{^flag_key, value1}] = results1
    [{^flag_key, value2}] = results2

    # Both should see enabled flag (enable-wins semantics)
    assert value1 == true
    assert value2 == true

    # Final clocks should be compatible (merged state)
    merged_clock = VectorClock.merge(final_clock1, final_clock2)
    assert VectorClock.compare(merged_clock, final_clock1) in [:equal, :after]
    assert VectorClock.compare(merged_clock, final_clock2) in [:equal, :after]

    # Clean up
    TestSetup.stop_nodes(nodes)
  end

  test "causal dependencies are respected across multiple operations" do
    # Test a chain of causal dependencies: A -> B -> C

    # Start three nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:chain_node1, :chain_node2, :chain_node3])
    [node1, node2, node3] = nodes

    # Wait for LinkLayer discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    counter_key = {"chain", Counter_PN_OB, "operations"}

    # Operation A on node1: increment by 1
    {:ok, clock_a} =
      :rpc.call(node1, Minidote, :update_objects, [
        [{counter_key, :increment, 1}],
        VectorClock.new()
      ])

    # Wait for replication
    Process.sleep(100)

    # Operation B on node2: increment by 10 (depends on A)
    {:ok, clock_b} =
      :rpc.call(node2, Minidote, :update_objects, [[{counter_key, :increment, 10}], clock_a])

    # Wait for replication
    Process.sleep(100)

    # Operation C on node3: increment by 100 (depends on B, which depends on A)
    {:ok, clock_c} =
      :rpc.call(node3, Minidote, :update_objects, [[{counter_key, :increment, 100}], clock_b])

    # Wait for final replication
    Process.sleep(200)

    # All nodes should see final value: 1 + 10 + 100 = 111
    {:ok, results1, _} =
      :rpc.call(node1, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    {:ok, results2, _} =
      :rpc.call(node2, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    {:ok, results3, _} =
      :rpc.call(node3, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    [{^counter_key, value1}] = results1
    [{^counter_key, value2}] = results2
    [{^counter_key, value3}] = results3

    assert value1 == 111
    assert value2 == 111
    assert value3 == 111

    # Verify causal ordering in clocks: clock_a -> clock_b -> clock_c
    assert VectorClock.before?(clock_a, clock_b)
    assert VectorClock.before?(clock_b, clock_c)
    # Transitivity
    assert VectorClock.before?(clock_a, clock_c)

    # Clean up
    TestSetup.stop_nodes(nodes)
  end
end
