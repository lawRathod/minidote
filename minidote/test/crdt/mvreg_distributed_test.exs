defmodule MVRegDistributedTest do
  use ExUnit.Case

  @moduletag :distributed

  test "true concurrent assignments in distributed setting" do
    # This test demonstrates MVReg behavior with truly concurrent operations
    # In a real distributed system, nodes can write without seeing each other's updates

    # Start two nodes with LinkLayer auto-discovery
    nodes = TestSetup.start_nodes_with_linklayer([:node1, :node2])
    [node1, node2] = nodes

    # Wait for LinkLayer discovery
    assert :ok = TestSetup.wait_for_linklayer_discovery(nodes)

    reg_key = {"distributed", MVReg_OB, "value"}

    # Both nodes write concurrently (neither sees the other's write when generating downstream)
    task1 =
      Task.async(fn ->
        :rpc.call(node1, Minidote, :update_objects, [[{reg_key, :assign, "node1-value"}], 0])
      end)

    task2 =
      Task.async(fn ->
        :rpc.call(node2, Minidote, :update_objects, [[{reg_key, :assign, "node2-value"}], 0])
      end)

    # Wait for both writes
    Task.await(task1)
    Task.await(task2)

    # Allow time for replication
    Process.sleep(100)

    # Read from either node should show both values
    {:ok, results, _} = :rpc.call(node1, Minidote, :read_objects, [[reg_key], 0])
    [{^reg_key, values}] = results

    # Should have both concurrent values
    sorted_values = Enum.sort(values)
    assert sorted_values == ["node1-value", "node2-value"]

    # Clean up
    TestSetup.stop_nodes(nodes)
  end
end
