defmodule Minidote do
  require Logger
  alias VectorClock

  @moduledoc """
  Main API module for Minidote, a distributed CRDT (Conflict-free Replicated Data Type) system.

  Minidote provides a template for building distributed applications with CRDTs that can be 
  replicated across multiple nodes while maintaining eventual consistency. The system uses 
  vector clocks for causal ordering and supports various CRDT types including counters, 
  sets, registers, and flags.

  ## Key concepts

  - **Keys**: Objects are identified by `{namespace, crdt_type, id}` tuples
  - **Vector Clocks**: Used for causal ordering of operations across distributed nodes
  - **Session Guarantees**: Read-your-writes and causal consistency guarantees
  - **Eventually Consistent**: All nodes converge to the same state given the same operations

  ## Example

      # Start the system
      {:ok, _pid} = Minidote.start_link(Minidote.Server)
      
      # Define a counter key
      counter_key = {"metrics", Counter_PN_OB, "page_views"}
      
      # Update the counter
      {:ok, clock1} = Minidote.update_objects([{counter_key, :increment, 5}])
      
      # Read the current value
      {:ok, [{^counter_key, value}], _clock2} = Minidote.read_objects([counter_key], clock1)
      
      # value will be 5
  """

  @type key :: {namespace :: binary(), crdt_type :: CRDT.t(), id :: binary()}
  @type clock :: VectorClock.t()
  @type update :: {key(), operation :: atom(), args :: any()} | {key(), operation :: atom()}
  @type read_result :: {key(), CRDT.value()}

  @doc """
  Starts a Minidote server with the given name.

  This function initializes the distributed CRDT system, including vector clock management,
  broadcast layer for distributed communication, and CRDT storage.

  ## Parameters

  - `server_name`: The name to register the GenServer process under

  ## Returns

  - `{:ok, pid}` on successful startup
  - `{:error, reason}` if startup fails

  ## Examples

      {:ok, _pid} = Minidote.start_link(Minidote.Server)
  """
  @spec start_link(atom()) :: GenServer.on_start()
  def start_link(server_name) do
    Minidote.Server.start_link(server_name)
  end

  @doc """
  Reads CRDT objects with causal consistency guarantees.

  This function reads the current values of the specified CRDT objects. It respects
  causal ordering - if the provided clock indicates dependencies that haven't been
  satisfied yet, the operation may wait until those dependencies are resolved.

  ## Parameters

  - `objects`: List of CRDT keys to read
  - `clock`: Vector clock representing causal dependencies (use empty clock if none)

  ## Returns

  - `{:ok, results, new_clock}`: Success with read results and updated vector clock
  - `{:error, reason}`: Error occurred during read operation

  ## Examples

      # Read without dependencies
      {:ok, results, clock} = Minidote.read_objects([counter_key], VectorClock.new())
      
      # Read with causal dependency
      {:ok, results, clock2} = Minidote.read_objects([counter_key], some_clock)
  """
  @spec read_objects([key()], clock()) ::
          {:ok, [read_result()], clock()} | {:error, any()}
  def read_objects(objects, clock) do
    Logger.notice("#{node()}: read_objects(#{inspect(objects)}, #{inspect(clock)})")
    # Convert legacy clock formats to vector clocks
    vector_clock = normalize_clock(clock)
    GenServer.call(Minidote.Server, {:read_objects, objects, vector_clock})
  end

  @doc """
  Updates CRDT objects with the given operations.

  This function applies operations to CRDT objects and broadcasts the effects to other
  nodes in the distributed system. The operations respect causal ordering and will
  wait for dependencies if necessary.

  ## Parameters

  - `updates`: List of update operations in the form `{key, operation}` or `{key, operation, args}`
  - `clock`: Vector clock representing causal dependencies

  ## Returns

  - `{:ok, new_clock}`: Success with updated vector clock
  - `{:error, reason}`: Error occurred during update (e.g., invalid operation)

  ## Examples

      # Simple increment
      {:ok, clock1} = Minidote.update_objects([{counter_key, :increment}])
      
      # Increment with value
      {:ok, clock2} = Minidote.update_objects([{counter_key, :increment, 5}], clock1)
      
      # Multiple operations
      updates = [
        {counter_key, :increment, 2},
        {set_key, :add, "item1"}
      ]
      {:ok, clock3} = Minidote.update_objects(updates, clock2)
  """
  @spec update_objects([update()], clock()) :: {:ok, clock()} | {:error, any()}
  def update_objects(updates, clock) do
    Logger.notice("#{node()}: update_objects(#{inspect(updates)}, #{inspect(clock)})")
    # Convert legacy clock formats to vector clocks
    vector_clock = normalize_clock(clock)
    GenServer.call(Minidote.Server, {:update_objects, updates, vector_clock})
  end

  @doc """
  Reads CRDT objects without specifying causal dependencies.

  This is a convenience function that uses an empty vector clock, meaning
  it will read the current state without waiting for any specific causal dependencies.

  ## Parameters

  - `objects`: List of CRDT keys to read

  ## Returns

  Same as `read_objects/2` but with an empty vector clock as dependency.

  ## Examples

      {:ok, results, clock} = Minidote.read_objects([counter_key])
  """
  @spec read_objects([key()]) :: {:ok, [read_result()], clock()} | {:error, any()}
  def read_objects(objects) do
    read_objects(objects, VectorClock.new())
  end

  @doc """
  Updates CRDT objects without specifying causal dependencies.

  This is a convenience function that uses an empty vector clock, meaning
  the operations don't wait for any specific causal dependencies.

  ## Parameters

  - `updates`: List of update operations

  ## Returns

  Same as `update_objects/2` but with an empty vector clock as dependency.

  ## Examples

      {:ok, clock} = Minidote.update_objects([{counter_key, :increment, 5}])
  """
  @spec update_objects([update()]) :: {:ok, clock()} | {:error, any()}
  def update_objects(updates) do
    update_objects(updates, VectorClock.new())
  end

  @doc """
  Test function that returns `:world`.

  This is a simple test function used for basic connectivity testing.
  """
  @spec hello() :: :world
  def hello do
    :world
  end

  # Helper function to handle backward compatibility with old clock formats
  @spec normalize_clock(any()) :: clock()
  defp normalize_clock(clock) do
    cond do
      # Already a vector clock
      is_map(clock) -> clock
      # Legacy logical clock - start fresh
      is_integer(clock) -> VectorClock.new()
      # Test cases that ignore clocks
      clock == :ignore -> VectorClock.new()
      # Nil clock
      is_nil(clock) -> VectorClock.new()
      # Fallback for any other format
      true -> VectorClock.new()
    end
  end
end
