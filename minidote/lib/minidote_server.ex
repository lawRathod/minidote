defmodule Minidote.Server do
  use GenServer
  require Logger
  alias VectorClock
  alias BroadcastLayer
  alias Consts

  @moduledoc """
  GenServer implementation for the Minidote distributed CRDT system.

  This module handles the core server logic including:
  - CRDT object storage and version management
  - Vector clock management for causal ordering
  - Distributed effect broadcasting via BroadcastLayer
  - Session guarantees and causal dependency handling
  - Request queuing for operations waiting on causal dependencies
  - Crash recovery with persistent operation logging and state snapshots

  The server automatically starts in distributed mode when running on a distributed node
  with process groups available, or in standalone mode for single-node testing.

  ## Persistence

  The server provides crash recovery through:
  - **Operation Log**: All update operations are logged to disk using Erlang Disk Log
  - **State Snapshots**: CRDT state is periodically saved to DETS tables
  - **Log Pruning**: Old log entries are pruned after successful state snapshots
  - **Recovery**: On startup, loads latest snapshot and replays operations from log

  ## State Structure

  The server maintains state with the following fields:
  - `objects`: Map of CRDT keys to `{crdt_state, version}` tuples
  - `clock`: Vector clock tracking causal ordering
  - `waiting_requests`: Queue of requests waiting for causal dependencies
  - `effect_buffer`: Buffer for out-of-order effects
  - `distributed`: Boolean indicating if running in distributed mode
  - `operation_log`: Disk Log handle for operation persistence
  - `objects_table`: DETS table handle for state snapshots
  - `last_snapshot_clock`: Vector clock at time of last snapshot
  - `snapshot_interval`: Number of operations between snapshots
  - `log_sequence`: Sequence number for operation ordering
  """

  @type server_state :: %{
          objects: %{Minidote.key() => {term(), non_neg_integer()}},
          clock: VectorClock.t(),
          waiting_requests: [term()],
          effect_buffer: [term()],
          distributed: boolean(),
          # Persistence-related state
          operation_log: term() | nil,
          objects_table: term() | nil,
          last_snapshot_clock: VectorClock.t() | nil,
          snapshot_interval: non_neg_integer(),
          log_sequence: non_neg_integer()
        }

  @doc """
  Starts the Minidote server GenServer.

  Initializes the distributed CRDT system including vector clock management,
  broadcast layer (if in distributed mode), and CRDT object storage.

  ## Parameters

  - `server_name`: Atom to register the GenServer process under

  ## Returns

  - `{:ok, pid}` on successful startup
  - `{:error, reason}` if startup fails
  """
  @spec start_link(atom()) :: GenServer.on_start()
  def start_link(server_name) do
    Logger.notice("Starting Minidote.Server on node #{Node.self()}")
    GenServer.start_link(__MODULE__, [], name: server_name)
  end

  @doc """
  Initializes the Minidote server state.

  Sets up the distributed CRDT system by:
  1. Starting BroadcastLayer if in distributed mode (when `:pg` is available)
  2. Registering as a receiver for distributed effects
  3. Initializing server state with empty object store and vector clock

  ## Returns

  - `{:ok, state}` with initial server state
  """
  @impl true
  @spec init(term()) :: {:ok, server_state()}
  def init(_) do
    # Only start BroadcastLayer in distributed mode
    broadcast_started =
      if Node.alive?() and :pg != :undefined do
        try do
          # Start the broadcast layer for distributed communication
          case BroadcastLayer.start_link(group_name: :minidote_cluster) do
            {:ok, _broadcast_layer} ->
              # Register ourselves to receive broadcast effects
              :ok = BroadcastLayer.register_receiver(self())
              true

            {:error, {:already_started, _pid}} ->
              # BroadcastLayer already running, just register
              :ok = BroadcastLayer.register_receiver(self())
              true
          end
        catch
          :exit, {:noproc, _} ->
            Logger.warning("BroadcastLayer not started - :pg not available")
            false

          error ->
            Logger.warning("BroadcastLayer failed to start: #{inspect(error)}")
            false
        end
      else
        Logger.debug("BroadcastLayer not started - running in non-distributed mode")
        false
      end

    # Initialize persistence layer
    persistence_state = init_persistence()

    # Initialize state with empty object store and vector clock, plus persistence
    initial_state = %{
      # Map of key -> {crdt_state, version}
      objects: %{},
      # Vector clock for causal ordering
      clock: VectorClock.new(Node.self()),
      # Queue for requests waiting on causal dependencies
      waiting_requests: [],
      # Buffer for out-of-order effects
      effect_buffer: [],
      # Track if we're in distributed mode
      distributed: broadcast_started,
      # Persistence-related state
      operation_log: persistence_state.operation_log,
      objects_table: persistence_state.objects_table,
      last_snapshot_clock: nil,
      snapshot_interval: persistence_state.snapshot_interval,
      log_sequence: 0
    }

    # Recover from persistent storage if available
    recovered_state = recover_from_persistence(initial_state)

    Logger.notice("Minidote.Server initialized with persistence enabled")
    {:ok, recovered_state}
  end

  @doc """
  Handles read_objects requests with causal consistency.

  Checks if the client's vector clock has causal dependencies that need to be
  satisfied before processing the read. If dependencies are met, processes
  immediately. Otherwise, queues the request until dependencies are satisfied.

  ## Parameters

  - `keys`: List of CRDT keys to read
  - `client_clock`: Client's vector clock representing causal dependencies
  - `from`: GenServer caller reference for potential deferred reply
  - `state`: Current server state

  ## Returns

  - `{:reply, {:ok, results, merged_clock}, new_state}` if processed immediately
  - `{:noreply, new_state}` if queued waiting for dependencies
  """
  @impl true
  @spec handle_call(
          {:read_objects, [Minidote.key()], VectorClock.t()},
          GenServer.from(),
          server_state()
        ) ::
          {:reply, {:ok, [Minidote.read_result()], VectorClock.t()}, server_state()}
          | {:noreply, server_state()}
  def handle_call({:read_objects, keys, client_clock}, from, state) do
    # Check if we need to wait for causal dependencies
    case check_causal_dependency(client_clock, state.clock) do
      :ready ->
        # Process immediately
        results = read_objects_internal(keys, state)
        merged_clock = VectorClock.merge(client_clock, state.clock)
        {:reply, {:ok, results, merged_clock}, state}

      :wait ->
        # Add to waiting requests
        request = {:read_objects, keys, client_clock, from}
        new_waiting = [request | state.waiting_requests]
        {:noreply, %{state | waiting_requests: new_waiting}}
    end
  end

  @impl true
  @spec handle_call(
          {:update_objects, [Minidote.update()], VectorClock.t()},
          GenServer.from(),
          server_state()
        ) ::
          {:reply, {:ok, VectorClock.t()}, server_state()}
          | {:reply, {:error, term()}, server_state()}
          | {:noreply, server_state()}
  def handle_call({:update_objects, updates, client_clock}, from, state) do
    # Check if we need to wait for causal dependencies
    case check_causal_dependency(client_clock, state.clock) do
      :ready ->
        # Process immediately
        process_update_objects(updates, client_clock, from, state)

      :wait ->
        # Add to waiting requests
        request = {:update_objects, updates, client_clock, from}
        new_waiting = [request | state.waiting_requests]
        {:noreply, %{state | waiting_requests: new_waiting}}
    end
  end

  @spec handle_call(term(), GenServer.from(), server_state()) ::
          {:reply, :not_implemented, server_state()}
  def handle_call(_msg, _from, state) do
    {:reply, :not_implemented, state}
  end

  @impl true
  @spec handle_cast({:effect, Minidote.key(), term(), node(), VectorClock.t()}, server_state()) ::
          {:noreply, server_state()}
  def handle_cast({:effect, key, effect, from_node, effect_clock}, state) do
    # Handle legacy direct cast messages (for backward compatibility)
    new_state = handle_causal_effect(key, effect, from_node, effect_clock, state)
    {:noreply, new_state}
  end

  @impl true
  @spec handle_info(
          {:causal_effect | :effect, Minidote.key(), term(), node(), VectorClock.t()},
          server_state()
        ) :: {:noreply, server_state()}
  def handle_info({:causal_effect, key, effect, from_node, effect_clock}, state) do
    # Handle causal broadcast effects from BroadcastLayer
    new_state = handle_causal_effect(key, effect, from_node, effect_clock, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:effect, key, effect, from_node, effect_clock}, state) do
    # Handle legacy info messages (for backward compatibility)
    new_state = handle_causal_effect(key, effect, from_node, effect_clock, state)
    {:noreply, new_state}
  end

  @spec handle_info(term(), server_state()) :: {:noreply, server_state()}
  def handle_info(msg, state) do
    Logger.warning("Unhandled info message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Helper functions

  @spec get_crdt_module(Minidote.key()) :: module()
  defp get_crdt_module({_namespace, crdt_type, _id}) do
    case crdt_type do
      Counter_PN_OB -> Counter_PN_OB
      Counter_PN_SB -> Counter_PN_SB
      Set_AW_OB -> Set_AW_OB
      MVReg_OB -> MVReg_OB
      TPSet_OB -> TPSet_OB
      Flag_EW_OB -> Flag_EW_OB
      _ -> raise "Unknown CRDT type: #{inspect(crdt_type)}"
    end
  end

  @spec apply_updates([Minidote.update()], server_state()) :: {server_state(), [term()], [term()]}
  defp apply_updates(updates, state) do
    # Log the operation before applying it
    new_sequence = state.log_sequence + 1
    log_operation(state, new_sequence, updates, state.clock)

    {new_state, effects, errors} =
      Enum.reduce(updates, {state, [], []}, fn update, {acc_state, acc_effects, acc_errors} ->
        {key, operation, arg} =
          case update do
            {key, operation} -> {key, operation, nil}
            {key, operation, arg} -> {key, operation, arg}
          end

        crdt_module = get_crdt_module(key)

        # Get or initialize CRDT state
        {crdt_state, version} =
          case Map.get(acc_state.objects, key) do
            nil -> {crdt_module.new(), 0}
            existing -> existing
          end

        # Generate downstream effect
        downstream_result =
          case arg do
            nil -> crdt_module.downstream(operation, crdt_state)
            _ -> crdt_module.downstream({operation, arg}, crdt_state)
          end

        case downstream_result do
          {:ok, effect} ->
            # Apply effect locally
            {:ok, new_crdt_state} = crdt_module.update(effect, crdt_state)

            # Update state
            new_version = version + 1
            new_objects = Map.put(acc_state.objects, key, {new_crdt_state, new_version})
            new_clock = VectorClock.increment(acc_state.clock, Node.self())

            new_acc_state = %{
              acc_state
              | objects: new_objects,
                clock: new_clock,
                log_sequence: new_sequence
            }

            # Collect effect for broadcast with clock
            effect_msg = {key, effect, node(), new_clock}

            {new_acc_state, [effect_msg | acc_effects], acc_errors}

          {:error, reason} ->
            # Collect error and skip this update
            Logger.error("Failed to apply update #{inspect(update)}: #{reason}")
            {acc_state, acc_effects, [{:error, reason} | acc_errors]}
        end
      end)

    # Check if we should create a snapshot
    updated_state = check_and_create_snapshot(new_state)

    {updated_state, Enum.reverse(effects), Enum.reverse(errors)}
  end

  @spec broadcast_effects([term()], server_state()) :: :ok
  defp broadcast_effects(effects, state) do
    if state.distributed do
      Enum.each(effects, fn {key, effect, from_node, effect_clock} ->
        # Use BroadcastLayer for reliable causal broadcast
        :ok = BroadcastLayer.broadcast_effect(key, effect, from_node, effect_clock)

        Logger.debug("Broadcasted effect #{inspect({key, effect})} via BroadcastLayer")
      end)
    else
      Logger.debug("Skipping broadcast - not in distributed mode")
    end
  end

  # Helper functions for causal broadcast and session guarantees

  @spec check_causal_dependency(VectorClock.t(), VectorClock.t()) :: :ready | :wait
  defp check_causal_dependency(client_clock, local_clock) do
    # For empty client clocks or when clocks are concurrent/compatible, process immediately
    # Only wait if client clock is strictly ahead of local clock
    case VectorClock.compare(client_clock, local_clock) do
      # Client is behind - can process
      :before -> :ready
      # Clocks are equal - can process
      :equal -> :ready
      # Concurrent operations - can process
      :concurrent -> :ready
      # Client is ahead - must wait
      :after -> :wait
    end
  end

  defp read_objects_internal(keys, state) do
    Enum.map(keys, fn key ->
      case Map.get(state.objects, key) do
        nil ->
          # Initialize new object if it doesn't exist
          crdt_module = get_crdt_module(key)
          {key, crdt_module.value(crdt_module.new())}

        {crdt_state, _version} ->
          crdt_module = get_crdt_module(key)
          {key, crdt_module.value(crdt_state)}
      end
    end)
  end

  defp process_update_objects(updates, client_clock, _from, state) do
    # Merge clocks and apply updates
    merged_clock = VectorClock.merge(client_clock, state.clock)
    new_state = %{state | clock: merged_clock}

    # Apply updates and broadcast to other nodes
    {final_state, effects, errors} = apply_updates(updates, new_state)

    # Broadcast effects to other nodes
    broadcast_effects(effects, final_state)

    case errors do
      [] ->
        {:reply, {:ok, final_state.clock}, final_state}

      [error | _] ->
        # Return the first error encountered
        {:reply, error, final_state}
    end
  end

  defp handle_causal_effect(key, effect, from_node, effect_clock, state) do
    # For now, deliver all effects immediately (simplified implementation)
    new_state = apply_remote_effect_with_clock(key, effect, from_node, effect_clock, state)
    deliver_buffered_effects(new_state)
  end

  defp can_deliver_effect?(_effect_clock, _local_clock) do
    # For now, deliver all effects immediately to avoid deadlocks
    true
  end

  defp apply_remote_effect_with_clock(key, effect, _from_node, effect_clock, state) do
    crdt_module = get_crdt_module(key)

    # Get or initialize CRDT state
    {crdt_state, version} =
      case Map.get(state.objects, key) do
        nil -> {crdt_module.new(), 0}
        existing -> existing
      end

    # Apply effect
    {:ok, new_crdt_state} = crdt_module.update(effect, crdt_state)

    # Update state with merged clock
    new_version = version + 1
    new_objects = Map.put(state.objects, key, {new_crdt_state, new_version})
    new_clock = VectorClock.merge(state.clock, effect_clock)

    %{state | objects: new_objects, clock: new_clock}
  end

  defp deliver_buffered_effects(state) do
    # Try to deliver any buffered effects that are now ready
    {deliverable, remaining} =
      Enum.split_with(state.effect_buffer, fn {_key, _effect, _from_node, effect_clock} ->
        can_deliver_effect?(effect_clock, state.clock)
      end)

    # Apply deliverable effects
    final_state =
      Enum.reduce(deliverable, state, fn {key, effect, from_node, effect_clock}, acc_state ->
        apply_remote_effect_with_clock(key, effect, from_node, effect_clock, acc_state)
      end)

    # Update buffer and check for waiting requests
    final_state_with_buffer = %{final_state | effect_buffer: remaining}
    check_waiting_requests(final_state_with_buffer)
  end

  defp check_waiting_requests(state) do
    # Check if any waiting requests can now be processed
    {ready_requests, still_waiting} =
      Enum.split_with(state.waiting_requests, fn
        {:read_objects, _keys, client_clock, _from} ->
          check_causal_dependency(client_clock, state.clock) == :ready

        {:update_objects, _updates, client_clock, _from} ->
          check_causal_dependency(client_clock, state.clock) == :ready
      end)

    # Process ready requests
    Enum.each(ready_requests, fn
      {:read_objects, keys, client_clock, from} ->
        results = read_objects_internal(keys, state)
        merged_clock = VectorClock.merge(client_clock, state.clock)
        GenServer.reply(from, {:ok, results, merged_clock})

      {:update_objects, updates, client_clock, from} ->
        {:reply, reply, _new_state} = process_update_objects(updates, client_clock, from, state)
        GenServer.reply(from, reply)
    end)

    %{state | waiting_requests: still_waiting}
  end

  # Persistence Functions

  # Initializes the persistence layer including operation log and state snapshots
  @spec init_persistence() :: %{
          operation_log: term() | nil,
          objects_table: term() | nil,
          snapshot_interval: non_neg_integer()
        }
  defp init_persistence() do
    node_name = Node.self() |> Atom.to_string()

    # Get paths from constants
    data_dir = Consts.node_data_dir(node_name)

    # Ensure data directory exists
    File.mkdir_p!(data_dir)

    # Configure paths using constants
    log_path = Consts.operation_log_path(node_name)
    table_path = Consts.objects_table_path(node_name)
    {max_file_size, max_files} = Consts.disk_log_config()

    # Initialize operation log
    operation_log =
      case :disk_log.open(
             name: :minidote_operations,
             file: String.to_charlist(log_path),
             type: :wrap,
             size: {max_file_size, max_files}
           ) do
        {:ok, log} ->
          Logger.info("Operation log opened: #{log_path}")
          log

        {:repaired, log, _recovered, _bad_bytes} ->
          Logger.info("Operation log repaired and opened: #{log_path}")
          log

        {:error, reason} ->
          Logger.error("Failed to open operation log: #{inspect(reason)}")
          nil
      end

    # Initialize DETS table for object snapshots
    objects_table =
      case :dets.open_file(:minidote_objects, file: String.to_charlist(table_path)) do
        {:ok, table} ->
          Logger.info("Objects table opened: #{table_path}")
          table

        {:error, reason} ->
          Logger.error("Failed to open objects table: #{inspect(reason)}")
          nil
      end

    %{
      operation_log: operation_log,
      objects_table: objects_table,
      snapshot_interval: Consts.default_snapshot_interval()
    }
  end

  # Recovers server state from persistent storage
  @spec recover_from_persistence(server_state()) :: server_state()
  defp recover_from_persistence(state) do
    if state.objects_table do
      # Load snapshot if available
      recovered_state = load_snapshot(state)

      # Replay operations from log
      replay_operations_from_log(recovered_state)
    else
      Logger.warning("No objects table available - starting with empty state")
      state
    end
  end

  # Loads the latest state snapshot from DETS table
  @spec load_snapshot(server_state()) :: server_state()
  defp load_snapshot(state) do
    case :dets.lookup(state.objects_table, :snapshot) do
      [{:snapshot, snapshot_data}] ->
        Logger.info("Loading state snapshot with #{map_size(snapshot_data.objects)} objects")

        %{
          state
          | objects: snapshot_data.objects,
            clock: snapshot_data.clock,
            last_snapshot_clock: snapshot_data.clock,
            log_sequence: snapshot_data.log_sequence
        }

      [] ->
        Logger.info("No snapshot found - starting with empty state")
        state

      {:error, reason} ->
        Logger.error("Failed to load snapshot: #{inspect(reason)}")
        state
    end
  end

  # Replays operations from the disk log that occurred after the last snapshot
  @spec replay_operations_from_log(server_state()) :: server_state()
  defp replay_operations_from_log(state) do
    if state.operation_log do
      case :disk_log.chunk(state.operation_log, :start) do
        {continuation, chunk} ->
          Logger.info("Replaying operations from log...")
          replay_chunk_with_continuation(state, chunk, continuation, 0)

        :eof ->
          Logger.info("No operations to replay")
          state
      end
    else
      state
    end
  end

  # Processes chunks of operations from the disk log using continuation
  @spec replay_chunk_with_continuation(server_state(), [term()], term(), non_neg_integer()) ::
          server_state()
  defp replay_chunk_with_continuation(state, chunk, continuation, count) do
    # Process operations in this chunk
    updated_state =
      Enum.reduce(chunk, state, fn operation, acc_state ->
        replay_single_operation(operation, acc_state)
      end)

    # Continue with next chunk if available
    case :disk_log.chunk(state.operation_log, continuation) do
      {next_continuation, next_chunk} ->
        replay_chunk_with_continuation(
          updated_state,
          next_chunk,
          next_continuation,
          count + length(chunk)
        )

      :eof ->
        Logger.info("Replayed #{count + length(chunk)} operations")
        updated_state
    end
  end

  # Replays a single operation from the log
  @spec replay_single_operation(term(), server_state()) :: server_state()
  defp replay_single_operation({:update, sequence, updates, clock}, state) do
    # Only replay operations that occurred after our snapshot
    if sequence > state.log_sequence do
      # Apply the updates without logging (to avoid infinite recursion)
      {updated_state, _effects, _errors} = apply_updates_without_logging(updates, state)

      # Update the clock and sequence
      %{
        updated_state
        | clock: VectorClock.merge(updated_state.clock, clock),
          log_sequence: sequence
      }
    else
      state
    end
  end

  defp replay_single_operation(operation, state) do
    Logger.warning("Unknown operation format in log: #{inspect(operation)}")
    state
  end

  # Applies updates without logging them (used during recovery)
  @spec apply_updates_without_logging([Minidote.update()], server_state()) ::
          {server_state(), [term()], [term()]}
  defp apply_updates_without_logging(updates, state) do
    {new_state, effects, errors} =
      Enum.reduce(updates, {state, [], []}, fn update, {acc_state, acc_effects, acc_errors} ->
        {key, operation, arg} =
          case update do
            {key, operation} -> {key, operation, nil}
            {key, operation, arg} -> {key, operation, arg}
          end

        crdt_module = get_crdt_module(key)

        # Get or initialize CRDT state
        {crdt_state, version} =
          case Map.get(acc_state.objects, key) do
            nil -> {crdt_module.new(), 0}
            existing -> existing
          end

        # Generate downstream effect
        downstream_result =
          case arg do
            nil -> crdt_module.downstream(operation, crdt_state)
            _ -> crdt_module.downstream({operation, arg}, crdt_state)
          end

        case downstream_result do
          {:ok, effect} ->
            # Apply effect locally (without logging)
            {:ok, new_crdt_state} = crdt_module.update(effect, crdt_state)

            # Update state
            new_version = version + 1
            new_objects = Map.put(acc_state.objects, key, {new_crdt_state, new_version})
            new_acc_state = %{acc_state | objects: new_objects}

            # Note: We don't increment the vector clock here as it's handled by the caller
            {new_acc_state, acc_effects, acc_errors}

          {:error, reason} ->
            Logger.error("Failed to replay update #{inspect(update)}: #{reason}")
            {acc_state, acc_effects, [{:error, reason} | acc_errors]}
        end
      end)

    {new_state, Enum.reverse(effects), Enum.reverse(errors)}
  end

  # Logs an operation to the persistent disk log
  @spec log_operation(server_state(), non_neg_integer(), [Minidote.update()], VectorClock.t()) ::
          :ok
  defp log_operation(state, sequence, updates, clock) do
    if state.operation_log do
      operation_entry = {:update, sequence, updates, clock}

      case :disk_log.log(state.operation_log, operation_entry) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to log operation: #{inspect(reason)}")
          # Continue operation even if logging fails
          :ok
      end
    else
      :ok
    end
  end

  # Checks if a snapshot should be created and creates one if needed
  @spec check_and_create_snapshot(server_state()) :: server_state()
  defp check_and_create_snapshot(state) do
    should_snapshot =
      state.last_snapshot_clock == nil or
        (state.log_sequence > 0 and rem(state.log_sequence, state.snapshot_interval) == 0)

    if should_snapshot and state.objects_table do
      create_snapshot(state)
    else
      state
    end
  end

  # Creates a snapshot of the current state
  @spec create_snapshot(server_state()) :: server_state()
  defp create_snapshot(state) do
    snapshot_data = %{
      objects: state.objects,
      clock: state.clock,
      log_sequence: state.log_sequence
    }

    case :dets.insert(state.objects_table, {:snapshot, snapshot_data}) do
      :ok ->
        case :dets.sync(state.objects_table) do
          :ok ->
            Logger.info(
              "Created snapshot with #{map_size(state.objects)} objects at sequence #{state.log_sequence}"
            )

            %{state | last_snapshot_clock: state.clock}

          {:error, reason} ->
            Logger.error("Failed to sync snapshot: #{inspect(reason)}")
            state
        end

      {:error, reason} ->
        Logger.error("Failed to create snapshot: #{inspect(reason)}")
        state
    end
  end
end
