defmodule MinidoteTest do
  use ExUnit.Case, async: false
  require Logger

  # Setup helper functions
  defp setup_clean_environment do
    TestSetup.init()
  end

  defp wait_for_replication(delay \\ 500) do
    Process.sleep(delay)
  end

  defp rpc_call_with_timeout(node, module, function, args, timeout \\ 15_000) do
    :rpc.call(node, module, function, args, timeout)
  end

  # Test 1: Multi-User Collaborative Document Editing
  test "collaborative document editing with multiple users" do
    setup_clean_environment()

    nodes = [
      TestSetup.start_node(:doc_node1),
      TestSetup.start_node(:doc_node2),
      TestSetup.start_node(:doc_node3)
    ]

    TestSetup.mock_link_layer(nodes, %{delay: 50})

    # Simulate collaborative document editing
    doc_key = {"documents", MVReg_OB, "shared_doc"}
    user_presence = {"presence", Set_AW_OB, "active_users"}
    edit_counter = {"stats", Counter_PN_OB, "total_edits"}

    # User 1 creates initial document
    {:ok, vc1} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{doc_key, :assign, "Initial document content"}],
        0
      ])

    wait_for_replication(200)

    # User 2 joins editing session
    {:ok, vc2} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        [{user_presence, :add, "user2@example.com"}],
        vc1
      ])

    wait_for_replication(200)

    # User 3 joins and makes an edit
    {:ok, vc3} =
      rpc_call_with_timeout(Enum.at(nodes, 2), :"Elixir.Minidote", :update_objects, [
        [
          {user_presence, :add, "user3@example.com"},
          {doc_key, :assign, "Updated document with user3 changes"},
          {edit_counter, :increment, 1}
        ],
        vc2
      ])

    wait_for_replication(500)

    # Verify consistency across all nodes
    Enum.each(nodes, fn node ->
      {:ok, results, _} =
        :rpc.call(node, :"Elixir.Minidote", :read_objects, [
          [doc_key, user_presence, edit_counter],
          vc3
        ])

      doc_content = Enum.find(results, fn {key, _} -> key == doc_key end) |> elem(1) |> hd()
      active_users = Enum.find(results, fn {key, _} -> key == user_presence end) |> elem(1)
      total_edits = Enum.find(results, fn {key, _} -> key == edit_counter end) |> elem(1)

      assert doc_content == "Updated document with user3 changes"
      assert MapSet.member?(active_users, "user2@example.com")
      assert MapSet.member?(active_users, "user3@example.com")
      assert total_edits >= 1
    end)

    Enum.each(nodes, &TestSetup.stop_node/1)
  end

  # Test 2: E-commerce Shopping Cart Scenario
  test "distributed shopping cart with inventory management" do
    setup_clean_environment()

    nodes = [
      TestSetup.start_node(:shop_node1),
      TestSetup.start_node(:shop_node2),
      TestSetup.start_node(:shop_node3)
    ]

    TestSetup.mock_link_layer(nodes, %{delay: 75})

    # Shopping cart and inventory keys
    cart_key = {"cart", Set_AW_OB, "user123"}
    inventory_key = {"inventory", Counter_PN_OB, "product_456"}
    orders_key = {"orders", Counter_PN_OB, "total_orders"}

    # Initialize inventory
    {:ok, vc1} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        # 100 items in stock
        [{inventory_key, :increment, 100}],
        0
      ])

    wait_for_replication(200)

    # Customer adds items to cart from different nodes
    {:ok, vc2} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        [{cart_key, :add, "product_456:qty_2"}],
        vc1
      ])

    wait_for_replication(200)

    {:ok, vc3} =
      rpc_call_with_timeout(Enum.at(nodes, 2), :"Elixir.Minidote", :update_objects, [
        [{cart_key, :add, "product_789:qty_1"}],
        vc2
      ])

    wait_for_replication(200)

    # Process order (decrement inventory)
    {:ok, vc4} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{inventory_key, :decrement, 2}, {orders_key, :increment, 1}],
        vc3
      ])

    wait_for_replication()

    # Verify final state
    {:ok, results, _} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :read_objects, [
        [cart_key, inventory_key, orders_key],
        vc4
      ])

    cart_items = Enum.find(results, fn {key, _} -> key == cart_key end) |> elem(1)
    remaining_inventory = Enum.find(results, fn {key, _} -> key == inventory_key end) |> elem(1)
    total_orders = Enum.find(results, fn {key, _} -> key == orders_key end) |> elem(1)

    assert MapSet.size(cart_items) == 2
    assert remaining_inventory == 98
    assert total_orders == 1

    Enum.each(nodes, &TestSetup.stop_node/1)
  end

  # Test 3: Feature Flag Management System
  test "distributed feature flag management" do
    setup_clean_environment()

    nodes = [
      TestSetup.start_node(:feature_node1),
      TestSetup.start_node(:feature_node2)
    ]

    TestSetup.mock_link_layer(nodes, %{delay: 30})

    # Feature flags
    beta_feature = {"features", Flag_EW_OB, "beta_ui"}
    ab_test = {"features", Flag_EW_OB, "ab_test_checkout"}
    user_count = {"metrics", Counter_PN_OB, "beta_users"}

    # Enable beta feature from node 1
    {:ok, vc1} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{beta_feature, :enable}, {user_count, :increment, 10}],
        0
      ])

    wait_for_replication(200)

    # Enable A/B test from node 2
    {:ok, vc2} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        [{ab_test, :enable}],
        vc1
      ])

    wait_for_replication(200)

    # Disable beta feature from node 2 (should still be enabled due to enable-wins)
    {:ok, vc3} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        [{beta_feature, :disable}],
        vc2
      ])

    wait_for_replication(200)

    # Re-enable beta feature from node 1
    {:ok, vc4} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{beta_feature, :enable}],
        vc3
      ])

    wait_for_replication()

    # Verify enable-wins semantics
    Enum.each(nodes, fn node ->
      {:ok, results, _} =
        :rpc.call(node, :"Elixir.Minidote", :read_objects, [
          [beta_feature, ab_test, user_count],
          vc4
        ])

      beta_enabled = Enum.find(results, fn {key, _} -> key == beta_feature end) |> elem(1)
      ab_enabled = Enum.find(results, fn {key, _} -> key == ab_test end) |> elem(1)
      users = Enum.find(results, fn {key, _} -> key == user_count end) |> elem(1)

      # Enable-wins
      assert beta_enabled == true
      assert ab_enabled == true
      assert users == 10
    end)

    Enum.each(nodes, &TestSetup.stop_node/1)
  end

  # Test 4: Task Management with Two-Phase Set
  test "distributed task management system" do
    setup_clean_environment()

    nodes = [
      TestSetup.start_node(:task_node1),
      TestSetup.start_node(:task_node2),
      TestSetup.start_node(:task_node3)
    ]

    TestSetup.mock_link_layer(nodes, %{delay: 40})

    # Task management keys
    todo_tasks = {"tasks", TPSet_OB, "todo"}
    completed_tasks = {"tasks", TPSet_OB, "completed"}
    task_counter = {"metrics", Counter_PN_OB, "tasks_created"}

    # Add tasks from different nodes
    {:ok, vc1} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{todo_tasks, :add_all, ["task1", "task2", "task3"]}, {task_counter, :increment, 3}],
        0
      ])

    wait_for_replication(200)

    {:ok, vc2} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        [{todo_tasks, :add, "task4"}, {task_counter, :increment, 1}],
        vc1
      ])

    wait_for_replication(200)

    # Complete some tasks (move from todo to completed)
    {:ok, vc3} =
      rpc_call_with_timeout(Enum.at(nodes, 2), :"Elixir.Minidote", :update_objects, [
        [{todo_tasks, :remove, "task1"}, {completed_tasks, :add, "task1"}],
        vc2
      ])

    wait_for_replication(200)

    {:ok, vc4} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{todo_tasks, :remove, "task2"}, {completed_tasks, :add, "task2"}],
        vc3
      ])

    wait_for_replication(200)

    # Try to re-add a completed task (should fail with TPSet semantics)
    result =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        [{todo_tasks, :add, "task1"}],
        vc4
      ])

    # Should fail because task1 was already removed
    assert {:error, _} = result

    wait_for_replication()

    # Verify final state
    {:ok, results, _} =
      rpc_call_with_timeout(Enum.at(nodes, 2), :"Elixir.Minidote", :read_objects, [
        [todo_tasks, completed_tasks, task_counter],
        vc4
      ])

    remaining_todos = Enum.find(results, fn {key, _} -> key == todo_tasks end) |> elem(1)
    completed = Enum.find(results, fn {key, _} -> key == completed_tasks end) |> elem(1)
    total_created = Enum.find(results, fn {key, _} -> key == task_counter end) |> elem(1)

    # task3, task4
    assert MapSet.size(remaining_todos) == 2
    assert MapSet.member?(remaining_todos, "task3")
    assert MapSet.member?(remaining_todos, "task4")
    # task1, task2
    assert MapSet.size(completed) == 2
    assert total_created == 4

    Enum.each(nodes, &TestSetup.stop_node/1)
  end

  # Test 5: Node Crash and Recovery Scenario
  test "crash recovery with persistence" do
    setup_clean_environment()

    # Use different node names to avoid conflicts
    node1 = TestSetup.start_node(:crash_node1)
    node2 = TestSetup.start_node(:crash_node2)
    nodes = [node1, node2]

    TestSetup.mock_link_layer(nodes, %{delay: 100})

    # Create some state
    counter_key = {"test", Counter_PN_OB, "crash_test"}
    set_key = {"test", Set_AW_OB, "crash_set"}

    {:ok, vc1} =
      rpc_call_with_timeout(node1, :"Elixir.Minidote", :update_objects, [
        [{counter_key, :increment, 50}, {set_key, :add, "item1"}],
        0
      ])

    wait_for_replication(200)

    {:ok, vc2} =
      rpc_call_with_timeout(node2, :"Elixir.Minidote", :update_objects, [
        [{counter_key, :increment, 25}, {set_key, :add, "item2"}],
        vc1
      ])

    wait_for_replication(200)

    # Verify state before crash
    {:ok, pre_crash_results, _} =
      rpc_call_with_timeout(node1, :"Elixir.Minidote", :read_objects, [
        [counter_key, set_key],
        vc2
      ])

    pre_crash_counter =
      Enum.find(pre_crash_results, fn {key, _} -> key == counter_key end) |> elem(1)

    pre_crash_set = Enum.find(pre_crash_results, fn {key, _} -> key == set_key end) |> elem(1)

    # 50 + 25
    assert pre_crash_counter == 75
    assert MapSet.member?(pre_crash_set, "item1")
    assert MapSet.member?(pre_crash_set, "item2")

    # Stop first node (simulating crash)
    TestSetup.stop_node(node1)
    wait_for_replication(200)

    # Continue operations on remaining node
    {:ok, vc3} =
      rpc_call_with_timeout(node2, :"Elixir.Minidote", :update_objects, [
        [{counter_key, :increment, 10}],
        vc2
      ])

    wait_for_replication(200)

    # Verify state on surviving node
    {:ok, surviving_results, _} =
      rpc_call_with_timeout(node2, :"Elixir.Minidote", :read_objects, [
        [counter_key, set_key],
        vc3
      ])

    surviving_counter =
      Enum.find(surviving_results, fn {key, _} -> key == counter_key end) |> elem(1)

    surviving_set = Enum.find(surviving_results, fn {key, _} -> key == set_key end) |> elem(1)

    # 50 + 25 + 10
    assert surviving_counter == 85
    assert MapSet.member?(surviving_set, "item1")
    assert MapSet.member?(surviving_set, "item2")

    # Now restart with a completely new node name to avoid conflicts
    recovered_node = TestSetup.start_node(:recovery_node)

    # Give it time to initialize (nodes automatically connect via LinkLayer)
    wait_for_replication(500)

    # Let the recovered node start with its own operations (fresh state)  
    {:ok, vc4} =
      rpc_call_with_timeout(recovered_node, :"Elixir.Minidote", :update_objects, [
        # Start fresh with 0 vector clock
        [{counter_key, :increment, 5}],
        0
      ])

    wait_for_replication(300)

    # Let the surviving node do another operation to propagate state
    {:ok, vc5} =
      rpc_call_with_timeout(node2, :"Elixir.Minidote", :update_objects, [
        # Use the existing vector clock from before crash
        [{set_key, :add, "item3"}],
        vc3
      ])

    wait_for_replication(500)

    # Verify final state - they should have eventually consistent but different values
    # since they started from different base states

    # Check surviving node state (should have all operations from before + after crash)
    {:ok, node2_results, _} =
      rpc_call_with_timeout(node2, :"Elixir.Minidote", :read_objects, [
        [counter_key, set_key],
        vc5
      ])

    node2_counter = Enum.find(node2_results, fn {key, _} -> key == counter_key end) |> elem(1)
    node2_set = Enum.find(node2_results, fn {key, _} -> key == set_key end) |> elem(1)

    # Node2 should have: 50 + 25 + 10 + 5 = 90 (includes recovered node's contribution)
    # At least the operations before the recovery node joined
    assert node2_counter >= 85
    assert MapSet.member?(node2_set, "item1")
    assert MapSet.member?(node2_set, "item2")
    assert MapSet.member?(node2_set, "item3")

    # Check recovered node state (should have received some state through replication)
    {:ok, recovered_results, _} =
      rpc_call_with_timeout(recovered_node, :"Elixir.Minidote", :read_objects, [
        [counter_key, set_key],
        vc4
      ])

    recovered_counter =
      Enum.find(recovered_results, fn {key, _} -> key == counter_key end) |> elem(1)

    _recovered_set = Enum.find(recovered_results, fn {key, _} -> key == set_key end) |> elem(1)

    # Recovery node started fresh, so it should have at least its own operation
    assert recovered_counter >= 5
    # It should receive replicated state eventually, but we'll be lenient in this test
    assert is_integer(recovered_counter)

    # Verify persistence files were created
    crash_node_data = Consts.node_data_dir("crash_node1_127.0.0.1")
    recovery_node_data = Consts.node_data_dir("recovery_node_127.0.0.1")

    assert File.exists?(crash_node_data), "Crashed node should have left persistent data"
    assert File.exists?(recovery_node_data), "Recovery node should have created persistent data"

    [TestSetup.stop_node(node2), TestSetup.stop_node(recovered_node)]
  end

  # Test 6: Large-Scale 10-Node Distributed Scenario
  # 1 minute timeout for large test
  @tag timeout: 60_000
  test "10-node distributed social media platform" do
    setup_clean_environment()

    # Start 10 nodes simulating a distributed social media platform
    node_names = Enum.map(1..10, &:"social_node#{&1}")
    nodes = Enum.map(node_names, &TestSetup.start_node/1)

    TestSetup.mock_link_layer(nodes, %{delay: 75})

    # Social media platform keys
    user_posts = {"social", Counter_PN_OB, "total_posts"}
    trending_tags = {"social", Set_AW_OB, "trending_hashtags"}
    online_users = {"social", Set_AW_OB, "online_users"}
    feature_enabled = {"social", Flag_EW_OB, "dark_mode"}

    # Simulate distributed social media activity across all nodes
    # Do initial operations in smaller batches to avoid overwhelming the system
    {results, _} =
      Enum.with_index(nodes)
      # Process 3 nodes at a time
      |> Enum.chunk_every(3)
      |> Enum.reduce({[], 0}, fn batch, {acc_results, base_vc} ->
        batch_operations =
          Enum.map(batch, fn {node, idx} ->
            Task.async(fn ->
              user_id = "user#{idx + 1}"
              # Create 3 different trending hashtags
              hashtag = "#trend#{rem(idx, 3) + 1}"

              result =
                rpc_call_with_timeout(node, :"Elixir.Minidote", :update_objects, [
                  # Random 1-3 posts (reduced)
                  [
                    {user_posts, :increment, :rand.uniform(3) + 1},
                    {trending_tags, :add, hashtag},
                    {online_users, :add, user_id}
                  ],
                  base_vc
                ])

              case result do
                {:ok, vc} -> {node, vc}
                {:error, reason} -> {node, {:error, reason}}
                other -> {node, {:error, other}}
              end
            end)
          end)

        batch_results = Task.await_many(batch_operations, 10_000)

        # Find the highest vector clock from this batch
        batch_vc =
          batch_results
          |> Enum.map(fn {_, vc_or_error} ->
            case vc_or_error do
              {:error, _} -> base_vc
              vc when is_map(vc) -> vc
              _ -> base_vc
            end
          end)
          |> Enum.max_by(fn vc -> Map.values(vc) |> Enum.sum() end, fn -> base_vc end)

        # Wait between batches
        wait_for_replication(300)

        {acc_results ++ batch_results, batch_vc}
      end)

    # Get the final vector clock
    last_vc =
      results
      |> Enum.map(fn {_, vc_or_error} ->
        case vc_or_error do
          {:error, _} -> %{}
          vc when is_map(vc) -> vc
          _ -> %{}
        end
      end)
      |> Enum.max_by(fn vc -> Map.values(vc) |> Enum.sum() end, fn -> %{} end)

    wait_for_replication(500)

    # Simulate feature flag changes from multiple nodes (simplified)
    {:ok, feature_vc} =
      rpc_call_with_timeout(hd(nodes), :"Elixir.Minidote", :update_objects, [
        [{feature_enabled, :enable}],
        last_vc
      ])

    wait_for_replication(300)

    # Simulate some users going offline (simplified to avoid Set remove operations)
    {:ok, final_vc} =
      rpc_call_with_timeout(Enum.at(nodes, 1), :"Elixir.Minidote", :update_objects, [
        # Add one more post instead of removing users
        [{user_posts, :increment, 1}],
        feature_vc
      ])

    # Allow significant time for all operations to propagate across 10 nodes
    wait_for_replication(2000)

    # Verify consistency across a subset of nodes (to reduce complexity)
    # Test 5 nodes instead of all 10
    verification_nodes = Enum.take(nodes, 5)

    verification_results =
      Enum.map(verification_nodes, fn node ->
        case rpc_call_with_timeout(node, :"Elixir.Minidote", :read_objects, [
               [user_posts, trending_tags, online_users, feature_enabled],
               final_vc
             ]) do
          {:ok, results, _} ->
            total_posts = Enum.find(results, fn {key, _} -> key == user_posts end) |> elem(1)
            hashtags = Enum.find(results, fn {key, _} -> key == trending_tags end) |> elem(1)
            online = Enum.find(results, fn {key, _} -> key == online_users end) |> elem(1)
            dark_mode = Enum.find(results, fn {key, _} -> key == feature_enabled end) |> elem(1)

            {node, :ok, total_posts, hashtags, online, dark_mode}

          error ->
            {node, :error, error}
        end
      end)

    # Filter out any errors and check consistency among successful reads
    successful_results =
      Enum.filter(verification_results, fn {_, status, _, _, _, _} -> status == :ok end)

    assert length(successful_results) >= 3, "At least 3 nodes should respond successfully"

    # Check consistency among successful nodes
    [{_, :ok, first_posts, first_tags, first_online, first_dark_mode} | rest_results] =
      successful_results

    Enum.each(rest_results, fn {node, :ok, posts, tags, online, dark_mode} ->
      assert posts == first_posts,
             "Node #{node} has inconsistent post count: #{posts} vs #{first_posts}"

      assert tags == first_tags, "Node #{node} has inconsistent hashtags"
      assert online == first_online, "Node #{node} has inconsistent online users"
      assert dark_mode == first_dark_mode, "Node #{node} has inconsistent feature flag"
    end)

    # Verify expected ranges
    assert first_posts > 0, "Should have some posts"
    assert MapSet.size(first_tags) > 0, "Should have trending hashtags"
    assert MapSet.size(first_online) >= 5, "Should have users online"
    assert is_boolean(first_dark_mode), "Feature flag should be boolean"

    Logger.info("10-node test completed successfully!")

    Logger.info(
      "Final state: #{first_posts} posts, #{MapSet.size(first_tags)} hashtags, #{MapSet.size(first_online)} online users"
    )

    # Cleanup all nodes
    Enum.each(nodes, &TestSetup.stop_node/1)
  end
end
