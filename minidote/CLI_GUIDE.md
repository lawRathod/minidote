# Guide: Collaborative Document Editing

This guide shows how to start real Minidote nodes with auto-discovery and perform the collaborative document editing test scenario from `minidote_test.exs` test 1.

## Setup: Start 3 Real Nodes with Auto-Discovery

Minidote uses automatic node discovery through the `MINIDOTE_NODES` environment variable and Erlang process groups. Nodes will automatically find and connect to each other.

### Terminal 1: Node 1 (User 1)
```bash
export MINIDOTE_NODES="node1@localhost,node2@localhost,node3@localhost"
iex --sname node1@localhost --cookie minidote_cluster -S mix
```

In the iex session:
```elixir
# The Minidote.Server is automatically started by the application
# Check that it's running
Process.whereis(Minidote.Server)

# Check node info and auto-discovery
IO.puts("Node 1 started: #{inspect(Node.self())}")
IO.puts("Connected nodes: #{inspect(Node.list())}")

# Check BroadcastLayer nodes (this shows the Minidote cluster)
{:ok, cluster_nodes} = BroadcastLayer.get_nodes()
IO.puts("Minidote cluster nodes: #{inspect(cluster_nodes)}")
```

### Terminal 2: Node 2 (User 2)
```bash
export MINIDOTE_NODES="node1@localhost,node2@localhost,node3@localhost"
iex --sname node2@localhost --cookie minidote_cluster -S mix
```

In the iex session:
```elixir
# Node will automatically discover and connect to other nodes

# Check connections (should automatically connect)
IO.puts("Node 2 started: #{inspect(Node.self())}")
IO.puts("Connected nodes: #{inspect(Node.list())}")

# Verify server is running
Process.whereis(Minidote.Server)

# Check Minidote cluster membership
{:ok, cluster_nodes} = BroadcastLayer.get_nodes()
IO.puts("Minidote cluster nodes: #{inspect(cluster_nodes)}")
```

### Terminal 3: Node 3 (User 3)
```bash
export MINIDOTE_NODES="node1@localhost,node2@localhost,node3@localhost"
iex --sname node3@localhost --cookie minidote_cluster -S mix
```

In the iex session:
```elixir
# Node will automatically discover and connect to cluster

# Check connections (should automatically find node1 and node2)
IO.puts("Node 3 started: #{inspect(Node.self())}")
IO.puts("Connected nodes: #{inspect(Node.list())}")

# Verify server is running
Process.whereis(Minidote.Server)

# Check Minidote cluster membership
{:ok, cluster_nodes} = BroadcastLayer.get_nodes()
IO.puts("Minidote cluster nodes: #{inspect(cluster_nodes)}")
```

## Step 1: Define Document Keys (In all terminals)

Run this in **ALL three terminals**:
```elixir
# Document keys from the test (using exact same CRDT types)
doc_key = {"documents", MVReg_OB, "shared_doc"}
user_presence = {"presence", Set_AW_OB, "active_users"}
edit_counter = {"stats", Counter_PN_OB, "total_edits"}

IO.puts("Document keys defined:")
IO.puts("  doc_key: #{inspect(doc_key)}")
IO.puts("  user_presence: #{inspect(user_presence)}")
IO.puts("  edit_counter: #{inspect(edit_counter)}")
```

## Step 2: User 1 Creates Initial Document (Terminal 1)

In **Terminal 1** (node1):
```elixir
# User 1 creates the initial document content
{:ok, vc1} = Minidote.update_objects([
  {doc_key, :assign, "Initial document content"}
])

IO.puts("✓ Initial document created by User 1")
IO.puts("Vector clock vc1: #{inspect(vc1)}")

# Verify the document was created
{:ok, results, _clock} = Minidote.read_objects([doc_key])
[{^doc_key, content}] = results
IO.puts("Document content: #{inspect(content)}")
```

## Step 3: User 2 Joins Session (Terminal 2)

In **Terminal 2** (node2):
```elixir
# Read current state to get up-to-date clock
{:ok, _results, current_vc} = Minidote.read_objects([doc_key])

# User 2 joins the editing session by adding to presence set
{:ok, vc2} = Minidote.update_objects([
  {user_presence, :add, "user2@example.com"}
], current_vc)

IO.puts("✓ User 2 joined the session")
IO.puts("Vector clock vc2: #{inspect(vc2)}")

# Verify both document and presence
{:ok, results, _clock} = Minidote.read_objects([doc_key, user_presence])
doc_content = Enum.find(results, fn {key, _} -> key == doc_key end) |> elem(1)
active_users = Enum.find(results, fn {key, _} -> key == user_presence end) |> elem(1)

IO.puts("Document: #{inspect(doc_content)}")
IO.puts("Active users: #{inspect(active_users)}")
```

## Step 4: User 3 Joins and Makes Edit (Terminal 3)

In **Terminal 3** (node3):
```elixir
# Read current state for up-to-date vector clock
{:ok, _results, current_vc} = Minidote.read_objects([doc_key, user_presence])

# User 3 performs multiple operations in one transaction:
# 1. Join the session (add to presence set)
# 2. Update the document content
# 3. Increment the edit counter
{:ok, vc3} = Minidote.update_objects([
  {user_presence, :add, "user3@example.com"},
  {doc_key, :assign, "Updated document with user3 changes"},
  {edit_counter, :increment, 1}
], current_vc)

IO.puts("✓ User 3 joined and made edit")
IO.puts("Vector clock vc3: #{inspect(vc3)}")

# Verify all changes
{:ok, results, _clock} = Minidote.read_objects([doc_key, user_presence, edit_counter])
doc_content = Enum.find(results, fn {key, _} -> key == doc_key end) |> elem(1) |> hd()
active_users = Enum.find(results, fn {key, _} -> key == user_presence end) |> elem(1)
total_edits = Enum.find(results, fn {key, _} -> key == edit_counter end) |> elem(1)

IO.puts("Document: #{inspect(doc_content)}")
IO.puts("Active users: #{inspect(active_users)}")
IO.puts("Total edits: #{inspect(total_edits)}")
```

## Step 5: Verify Consistency Across All Nodes

Run this verification in **ALL three terminals** to check that all nodes have consistent state:

```elixir
# Read final state from this node
{:ok, results, final_vc} = Minidote.read_objects([
  doc_key, 
  user_presence, 
  edit_counter
])

# Extract results
doc_content = Enum.find(results, fn {key, _} -> key == doc_key end) |> elem(1) |> hd()
active_users = Enum.find(results, fn {key, _} -> key == user_presence end) |> elem(1)
total_edits = Enum.find(results, fn {key, _} -> key == edit_counter end) |> elem(1)

# Display current node's state
IO.puts("\n=== #{Node.self()} State ===")
IO.puts("Document content: #{inspect(doc_content)}")
IO.puts("Active users: #{inspect(active_users)}")
IO.puts("Total edits: #{inspect(total_edits)}")
IO.puts("Vector clock: #{inspect(final_vc)}")

# Verify expected values (same as test assertions)
IO.puts("\n=== Verification ===")
correct_content = doc_content == "Updated document with user3 changes"
has_user2 = MapSet.member?(active_users, "user2@example.com")
has_user3 = MapSet.member?(active_users, "user3@example.com")
enough_edits = total_edits >= 1

IO.puts("✓ Document content correct: #{correct_content}")
IO.puts("✓ User2 present: #{has_user2}")
IO.puts("✓ User3 present: #{has_user3}")
IO.puts("✓ Edit count >= 1: #{enough_edits}")

if correct_content and has_user2 and has_user3 and enough_edits do
  IO.puts("🎉 ALL CHECKS PASSED on #{Node.self()}!")
else
  IO.puts("❌ Some checks failed on #{Node.self()}")
end
```

## Step 6: Additional Experiments

Try these additional experiments to see how the distributed system behaves:

### Experiment 1: More Edits from Different Nodes
```elixir
# From any terminal, make more edits
{:ok, current_results, current_vc} = Minidote.read_objects([doc_key, edit_counter])

{:ok, new_vc} = Minidote.update_objects([
  {doc_key, :assign, "Final version from #{Node.self()}"},
  {edit_counter, :increment, 2}
], current_vc)

IO.puts("Made additional edit from #{Node.self()}")
```

### Experiment 2: Disconnect and Reconnect Nodes
```elixir
# In one terminal, disconnect from cluster
Node.disconnect(:node1@localhost)
Node.disconnect(:node2@localhost)

# Make some changes while disconnected
{:ok, vc_disconnected} = Minidote.update_objects([
  {edit_counter, :increment, 5}
])

# Reconnect
Node.connect(:node1@localhost)
Node.connect(:node2@localhost)

{:ok, results, _} = Minidote.read_objects([edit_counter])
```

## Expected Final Results

After completing all steps, all three nodes should show identical state:
- **Document content**: `"Updated document with user3 changes"`
- **Active users**: A set containing both `"user2@example.com"` and `"user3@example.com"`
- **Total edits**: At least `1` (could be more if you ran experiments)
- **Vector clocks**: Should be causally related across all nodes

## Troubleshooting

If nodes aren't auto-discovering:

### Check Environment Variable
```bash
echo $MINIDOTE_NODES
# Should show: node1@localhost,node2@localhost,node3@localhost
```

### Check Node Connectivity
```elixir
# Check if nodes can see each other
Node.ping(:node1@localhost)  # Should return :pong

# Check Erlang distribution
:net_adm.names()  # Should list all nodes

# Check what nodes auto-discovery is trying to connect to
nodes = :string.tokens(:os.getenv(~c"MINIDOTE_NODES", ~c""), ~c",")
for n <- nodes do
  :erlang.list_to_atom(n)
end
```

### Check Process Group Membership
```elixir
# Check if nodes joined the Minidote cluster process group
:pg.which_groups()  # Should show :minidote_cluster
:pg.get_members(:minidote_cluster)  # Should show all LinkLayer PIDs
```

### Manual Connection (if auto-discovery fails)
```elixir
# As fallback, manually connect nodes
Node.connect(:node1@localhost)
Node.connect(:node2@localhost)
```

### Verify BroadcastLayer
```elixir
# Check BroadcastLayer state
BroadcastLayer.get_state()

# Should show connected cluster nodes
{:ok, nodes} = BroadcastLayer.get_nodes()
IO.puts("Cluster size: #{length(nodes)}")
```