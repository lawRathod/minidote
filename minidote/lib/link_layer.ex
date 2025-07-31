defmodule LinkLayer do
  @moduledoc """
  Network abstraction layer for distributed node communication.

  LinkLayer provides a uniform API for network communication between nodes
  in a distributed system. It handles node discovery, connection management,
  and message routing through process groups.

  ## Architecture

  LinkLayer is implemented as a thin wrapper around LinkLayerDistr, which
  provides the actual distributed functionality using Erlang's `:pg` 
  (process groups) for node discovery and coordination.

  ## Features

  - **Automatic Discovery**: Nodes automatically discover each other via process groups
  - **Connection Management**: Handles connections and disconnections transparently
  - **Message Routing**: Routes messages between nodes in the cluster
  - **Fault Tolerance**: Handles node failures and network partitions

  ## Usage

  LinkLayer is typically used by BroadcastLayer to send CRDT effects
  between nodes:

      # Start LinkLayer for a cluster
      {:ok, ll_pid} = LinkLayer.start_link(:minidote_cluster)
      
      # Register to receive messages
      :ok = LinkLayer.register(ll_pid, self())
      
      # Send message to another node
      :ok = LinkLayer.send(ll_pid, effect_data, target_node_pid)
      
      # Get cluster information
      {:ok, all_nodes} = LinkLayer.all_nodes(ll_pid)
      {:ok, other_nodes} = LinkLayer.other_nodes(ll_pid)

  ## Node Discovery

  Nodes discover each other through:
  1. Environment variable `MINIDOTE_NODES` with comma-separated node names
  2. Process group membership in the specified group
  3. Automatic connection attempts to discovered nodes
  """

  @doc """
  Starts a LinkLayer instance for the specified process group.

  ## Parameters

  - `group_name`: Atom identifying the process group for node discovery

  ## Returns

  - `{:ok, pid}` on successful startup
  - `{:error, reason}` if startup fails

  ## Examples

      {:ok, ll_pid} = LinkLayer.start_link(:minidote_cluster)
  """
  @spec start_link(atom()) :: GenServer.on_start()
  def start_link(group_name) do
    LinkLayerDistr.start_link(group_name)
  end

  @doc """
  Sends data to a specific node in the cluster.

  ## Parameters

  - `ll`: LinkLayer GenServer PID
  - `data`: Data to send (any term)
  - `node`: Target node PID

  ## Returns

  - `:ok` on successful send
  - `{:error, reason}` if send fails

  ## Examples

      :ok = LinkLayer.send(ll_pid, {:crdt_effect, key, effect}, target_node)
  """
  @spec send(pid(), term(), pid()) :: :ok | {:error, term()}
  def send(ll, data, node) do
    GenServer.call(ll, {:send, data, node})
  end

  @doc """
  Registers a process to receive messages from other nodes.

  ## Parameters

  - `ll`: LinkLayer GenServer PID  
  - `receiver`: PID of process to receive messages

  ## Returns

  `:ok` on successful registration

  ## Examples

      :ok = LinkLayer.register(ll_pid, self())
  """
  @spec register(pid(), pid()) :: :ok
  def register(ll, receiver) do
    GenServer.call(ll, {:register, receiver})
  end

  @doc """
  Gets all nodes in the cluster (including this node).

  ## Parameters

  - `ll`: LinkLayer GenServer PID

  ## Returns

  - `{:ok, nodes}` - List of all node PIDs in cluster
  - `{:error, reason}` if operation fails

  ## Examples

      {:ok, all_nodes} = LinkLayer.all_nodes(ll_pid)
  """
  @spec all_nodes(pid()) :: {:ok, [pid()]} | {:error, term()}
  def all_nodes(ll) do
    GenServer.call(ll, :all_nodes)
  end

  @doc """
  Gets other nodes in the cluster (excluding this node).

  ## Parameters

  - `ll`: LinkLayer GenServer PID

  ## Returns

  - `{:ok, nodes}` - List of other node PIDs in cluster
  - `{:error, reason}` if operation fails

  ## Examples

      {:ok, other_nodes} = LinkLayer.other_nodes(ll_pid)
  """
  @spec other_nodes(pid()) :: {:ok, [pid()]} | {:error, term()}
  def other_nodes(ll) do
    GenServer.call(ll, :other_nodes)
  end

  @doc """
  Gets the PID representing this node in the cluster.

  ## Parameters

  - `ll`: LinkLayer GenServer PID

  ## Returns

  - `{:ok, node_pid}` - This node's PID in the cluster
  - `{:error, reason}` if operation fails

  ## Examples

      {:ok, this_node} = LinkLayer.this_node(ll_pid)
  """
  @spec this_node(pid()) :: {:ok, pid()} | {:error, term()}
  def this_node(ll) do
    GenServer.call(ll, :this_node)
  end
end
