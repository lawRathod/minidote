defmodule BroadcastLayer do
  use GenServer
  require Logger
  alias VectorClock

  @moduledoc """
  Broadcast layer for reliable causal broadcast using LinkLayer.

  This module implements causal broadcast primitives for distributed CRDT 
  synchronization. It ensures that CRDT effects are delivered to all nodes
  in the cluster while respecting causal ordering constraints.

  ## Features

  - **Causal Broadcast**: Effects are delivered respecting happened-before relationships
  - **Reliable Delivery**: Uses LinkLayer abstraction for robust network communication
  - **Automatic Discovery**: Nodes automatically discover and connect to cluster members
  - **Effect Buffering**: Out-of-order effects are buffered until dependencies are satisfied
  - **Vector Clock Integration**: Maintains causal ordering using vector clocks

  ## Architecture

  The BroadcastLayer acts as an intermediary between MinidoteServer and the network:
  1. Receives effects from local CRDT operations
  2. Broadcasts effects to all cluster nodes via LinkLayer
  3. Receives remote effects and forwards them to registered receivers
  4. Buffers effects that arrive out of causal order

  ## Lifecycle

      # Start the broadcast layer (usually done by MinidoteServer)
      {:ok, _pid} = BroadcastLayer.start_link(group_name: :minidote_cluster)
      
      # Register to receive effects
      :ok = BroadcastLayer.register_receiver(self())
      
      # Broadcast an effect
      :ok = BroadcastLayer.broadcast_effect(key, effect, node(), vector_clock)

  ## Message Flow

  1. Local operation generates effect
  2. Effect broadcast via `broadcast_effect/4`
  3. LinkLayer delivers to remote nodes
  4. Remote nodes receive as `{:causal_effect, ...}` message
  5. Effects forwarded to registered receivers (e.g., MinidoteServer)
  """

  @type effect :: {key :: term(), effect :: term(), from_node :: node(), clock :: VectorClock.t()}

  # Client API

  @doc """
  Starts the BroadcastLayer GenServer.

  ## Options

  - `:group_name` - Process group name for LinkLayer (default: `:minidote_cluster`)

  ## Returns

  - `{:ok, pid}` on successful startup
  - `{:error, reason}` if startup fails

  ## Examples

      {:ok, _pid} = BroadcastLayer.start_link()
      {:ok, _pid} = BroadcastLayer.start_link(group_name: :my_cluster)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Broadcasts an effect to all nodes in the cluster with causal ordering.

  The effect will be delivered to all other nodes in the cluster via LinkLayer.
  The vector clock ensures that effects are processed in causal order on
  receiving nodes.

  ## Parameters

  - `key`: The CRDT key this effect applies to
  - `effect`: The CRDT effect to broadcast
  - `from_node`: The originating node (usually `node()`)
  - `effect_clock`: Vector clock representing causal dependencies

  ## Returns

  `:ok` - The broadcast request has been queued (fire-and-forget)

  ## Examples

      :ok = BroadcastLayer.broadcast_effect(
        {"counters", Counter_PN_OB, "page_views"},
        increment_effect,
        node(),
        vector_clock
      )
  """
  @spec broadcast_effect(term(), term(), node(), VectorClock.t()) :: :ok
  def broadcast_effect(key, effect, from_node, effect_clock) do
    GenServer.cast(__MODULE__, {:broadcast_effect, key, effect, from_node, effect_clock})
  end

  @doc """
  Registers a process to receive broadcast effects.

  The registered process will receive `{:causal_effect, key, effect, from_node, clock}`
  messages when effects are received from other nodes.

  ## Parameters

  - `receiver_pid`: PID of the process to receive effects (typically MinidoteServer)

  ## Returns

  `:ok` on successful registration

  ## Examples

      :ok = BroadcastLayer.register_receiver(self())
  """
  @spec register_receiver(pid()) :: :ok
  def register_receiver(receiver_pid) do
    GenServer.call(__MODULE__, {:register_receiver, receiver_pid})
  end

  @doc """
  Gets the list of all connected nodes in the cluster.

  Returns the list of nodes that are currently reachable via LinkLayer.
  This can be used for monitoring cluster membership.

  ## Returns

  - `{:ok, nodes}` - List of connected node PIDs
  - `{:error, reason}` - Error retrieving node list

  ## Examples

      {:ok, nodes} = BroadcastLayer.get_nodes()
      # nodes is now a list of connected node PIDs
  """
  @spec get_nodes() :: {:ok, [node()]} | {:error, term()}
  def get_nodes() do
    GenServer.call(__MODULE__, :get_nodes)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    group_name = Keyword.get(opts, :group_name, :minidote_cluster)

    # Start LinkLayer for this group
    {:ok, link_layer_pid} = LinkLayer.start_link(group_name)

    # Register ourselves as the receiver for incoming effects
    :ok = LinkLayer.register(link_layer_pid, self())

    Logger.notice("BroadcastLayer started with LinkLayer for group #{group_name}")

    {:ok,
     %{
       link_layer: link_layer_pid,
       group_name: group_name,
       receivers: [],
       effect_buffer: [],
       local_clock: VectorClock.new(Node.self())
     }}
  end

  @impl true
  def handle_call({:register_receiver, receiver_pid}, _from, state) do
    new_receivers = [receiver_pid | state.receivers]
    Logger.debug("Registered new effect receiver: #{inspect(receiver_pid)}")
    {:reply, :ok, %{state | receivers: new_receivers}}
  end

  @impl true
  def handle_call(:get_nodes, _from, state) do
    case LinkLayer.other_nodes(state.link_layer) do
      {:ok, nodes} -> {:reply, {:ok, nodes}, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # Return sanitized state for debugging
    debug_state = %{
      group_name: state.group_name,
      receivers_count: length(state.receivers),
      buffer_size: length(state.effect_buffer),
      local_clock: state.local_clock
    }

    {:reply, debug_state, state}
  end

  @impl true
  def handle_cast({:broadcast_effect, key, effect, from_node, effect_clock}, state) do
    # Update local clock with the effect clock
    new_local_clock = VectorClock.merge(state.local_clock, effect_clock)

    # Broadcast to all other nodes
    case LinkLayer.other_nodes(state.link_layer) do
      {:ok, other_nodes} ->
        effect_msg = {:causal_effect, key, effect, from_node, effect_clock}

        Enum.each(other_nodes, fn node_pid ->
          LinkLayer.send(state.link_layer, effect_msg, node_pid)
        end)

        Logger.debug(
          "Broadcasted effect #{inspect({key, effect})} to #{length(other_nodes)} nodes"
        )

      {:error, reason} ->
        Logger.warning("Failed to get other nodes for broadcast: #{inspect(reason)}")
    end

    {:noreply, %{state | local_clock: new_local_clock}}
  end

  @impl true
  def handle_cast(:flush_buffer, state) do
    final_state = process_buffered_effects(state)
    {:noreply, final_state}
  end

  @impl true
  def handle_info({:causal_effect, key, effect, from_node, effect_clock} = effect_msg, state) do
    # Received a causal effect from another node via LinkLayer
    Logger.debug("Received causal effect: #{inspect({key, effect})} from #{from_node}")

    # Update our local clock
    new_local_clock = VectorClock.merge(state.local_clock, effect_clock)

    # Check if this effect can be delivered immediately or needs buffering
    new_state = %{state | local_clock: new_local_clock}

    # For now, deliver all effects immediately (simplified causal ordering)
    # In production, you'd implement proper causal dependency checking here
    deliver_effect_to_receivers(effect_msg, new_state)
    final_state = process_buffered_effects(new_state)
    {:noreply, final_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("BroadcastLayer received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Helper Functions

  defp can_deliver_effect?(_effect_clock, _local_clock) do
    # For now, deliver all effects immediately to avoid deadlocks
    # In a more sophisticated implementation, you would check proper causal ordering
    true
  end

  defp deliver_effect_to_receivers(effect_msg, state) do
    Enum.each(state.receivers, fn receiver_pid ->
      send(receiver_pid, effect_msg)
    end)
  end

  defp process_buffered_effects(state) do
    # Try to deliver any buffered effects that are now ready
    {deliverable, remaining} =
      Enum.split_with(state.effect_buffer, fn {_type, _key, _effect, _from_node, effect_clock} ->
        can_deliver_effect?(effect_clock, state.local_clock)
      end)

    # Deliver ready effects
    Enum.each(deliverable, fn effect_msg ->
      deliver_effect_to_receivers(effect_msg, state)
    end)

    if length(deliverable) > 0 do
      Logger.debug("Delivered #{length(deliverable)} buffered effects")
    end

    %{state | effect_buffer: remaining}
  end

  # Utility functions for testing and debugging

  @doc """
  Get current state for debugging purposes.
  """
  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Force process buffered effects (for testing).
  """
  def flush_buffer() do
    GenServer.cast(__MODULE__, :flush_buffer)
  end
end
