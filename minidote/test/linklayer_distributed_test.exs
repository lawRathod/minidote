defmodule LinkLayerDistributedTest do
  use ExUnit.Case
  alias VectorClock

  @moduletag :distributed

  test "LinkLayer auto-discovery and causal broadcast" do
    # Test that nodes can discover each other via LinkLayer and exchange effects

    # Start three nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:ll_node1, :ll_node2, :ll_node3])
    [node1, node2, node3] = nodes

    # Wait for LinkLayer discovery to complete
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    counter_key = {"linklayer", Counter_PN_OB, "test"}

    # Node1: Initial operation
    {:ok, clock1} =
      :rpc.call(node1, Minidote, :update_objects, [
        [{counter_key, :increment, 10}],
        VectorClock.new()
      ])

    # Node2: Operation that should see node1's update via LinkLayer
    {:ok, clock2} =
      :rpc.call(node2, Minidote, :update_objects, [
        [{counter_key, :increment, 5}],
        VectorClock.new()
      ])

    # Allow time for LinkLayer replication
    Process.sleep(500)

    # All nodes should see the final state (15)
    {:ok, results1, _} =
      :rpc.call(node1, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    {:ok, results2, _} =
      :rpc.call(node2, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    {:ok, results3, _} =
      :rpc.call(node3, Minidote, :read_objects, [[counter_key], VectorClock.new()])

    [{^counter_key, value1}] = results1
    [{^counter_key, value2}] = results2
    [{^counter_key, value3}] = results3

    # All nodes should converge to the same value
    assert value1 == 15
    assert value2 == 15
    assert value3 == 15

    # Verify that vector clocks show operations from multiple nodes
    assert VectorClock.get(clock1, :"ll_node1@127.0.0.1") > 0
    assert VectorClock.get(clock2, :"ll_node2@127.0.0.1") > 0

    # Clean up
    TestSetup.stop_nodes(nodes)
  end

  test "concurrent operations with LinkLayer broadcast" do
    # Test that concurrent operations work correctly with LinkLayer

    # Start two isolated node groups that will connect via LinkLayer
    nodes = TestSetup.start_nodes_with_linklayer([:conc1, :conc2])
    [node1, node2] = nodes

    # Wait for discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    set_key = {"concurrent", Set_AW_OB, "items"}

    # Concurrent operations on different nodes
    task1 =
      Task.async(fn ->
        :rpc.call(node1, Minidote, :update_objects, [
          [{set_key, :add, "from_node1"}],
          VectorClock.new()
        ])
      end)

    task2 =
      Task.async(fn ->
        :rpc.call(node2, Minidote, :update_objects, [
          [{set_key, :add, "from_node2"}],
          VectorClock.new()
        ])
      end)

    {:ok, _clock1} = Task.await(task1)
    {:ok, _clock2} = Task.await(task2)

    # Allow time for LinkLayer propagation
    Process.sleep(500)

    # Both nodes should see both items
    {:ok, results1, _} = :rpc.call(node1, Minidote, :read_objects, [[set_key], VectorClock.new()])
    {:ok, results2, _} = :rpc.call(node2, Minidote, :read_objects, [[set_key], VectorClock.new()])

    [{^set_key, items1}] = results1
    [{^set_key, items2}] = results2

    sorted_items1 = Enum.sort(items1)
    sorted_items2 = Enum.sort(items2)

    assert sorted_items1 == ["from_node1", "from_node2"]
    assert sorted_items2 == ["from_node1", "from_node2"]

    # Clean up
    TestSetup.stop_nodes(nodes)
  end

  test "LinkLayer handles node failures gracefully" do
    # Test that remaining nodes continue to work when one node fails

    nodes = TestSetup.start_nodes_with_linklayer([:fail1, :fail2, :fail3])
    [node1, node2, node3] = nodes

    # Wait for discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    reg_key = {"failure", MVReg_OB, "test"}

    # All nodes write initial values
    {:ok, _} =
      :rpc.call(node1, Minidote, :update_objects, [
        [{reg_key, :assign, "node1_value"}],
        VectorClock.new()
      ])

    {:ok, _} =
      :rpc.call(node2, Minidote, :update_objects, [
        [{reg_key, :assign, "node2_value"}],
        VectorClock.new()
      ])

    {:ok, _} =
      :rpc.call(node3, Minidote, :update_objects, [
        [{reg_key, :assign, "node3_value"}],
        VectorClock.new()
      ])

    Process.sleep(300)

    # Stop node3 (simulating failure)
    TestSetup.stop_node(node3)

    # Remaining nodes should continue working
    {:ok, _} =
      :rpc.call(node1, Minidote, :update_objects, [
        [{reg_key, :assign, "after_failure"}],
        VectorClock.new()
      ])

    Process.sleep(200)

    # Node1 and Node2 should still be able to read
    {:ok, results1, _} = :rpc.call(node1, Minidote, :read_objects, [[reg_key], VectorClock.new()])
    {:ok, results2, _} = :rpc.call(node2, Minidote, :read_objects, [[reg_key], VectorClock.new()])

    [{^reg_key, values1}] = results1
    [{^reg_key, values2}] = results2

    # Both should see the update after failure
    assert "after_failure" in values1
    assert "after_failure" in values2

    # Clean up remaining nodes
    TestSetup.stop_nodes([node1, node2])
  end

  test "BroadcastLayer state inspection" do
    # Test that we can inspect BroadcastLayer state for debugging

    nodes = TestSetup.start_nodes_with_linklayer([:debug1, :debug2])
    [node1, node2] = nodes

    # Wait for discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    # Check BroadcastLayer state on both nodes
    state1 = :rpc.call(node1, BroadcastLayer, :get_state, [])
    state2 = :rpc.call(node2, BroadcastLayer, :get_state, [])

    # Both should have the same group name
    assert state1.group_name == :minidote_cluster
    assert state2.group_name == :minidote_cluster

    # Both should have at least one receiver (the MinidoteServer)
    assert state1.receivers_count >= 1
    assert state2.receivers_count >= 1

    # Vector clocks should be present
    assert is_map(state1.local_clock)
    assert is_map(state2.local_clock)

    # Clean up
    TestSetup.stop_nodes(nodes)
  end
end
