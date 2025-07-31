defmodule TPSet_OB do
  @behaviour CRDT

  @moduledoc """
  Operation-based Two-Phase Set CRDT.

  A Two-Phase Set (2P-Set) is a CRDT that supports both add and remove operations
  with a key restriction: once an element is removed, it cannot be re-added.
  This ensures convergence by preventing add/remove conflicts.

  The implementation maintains two grow-only sets:
  - **Added Set**: Elements that have been added
  - **Removed Set**: Elements that have been removed (tombstones)

  ## Features

  - **Add Elements**: Add single elements or multiple elements
  - **Remove Elements**: Remove elements permanently (creates tombstones)
  - **No Re-addition**: Once removed, elements cannot be added again
  - **Deterministic**: Clear conflict resolution (remove wins permanently)

  ## Operations

  - `{:add, element}` - Add a single element (if not already removed)
  - `{:add_all, [elements]}` - Add multiple elements
  - `{:remove, element}` - Remove a single element (if it exists)
  - `{:remove_all, [elements]}` - Remove multiple elements

  ## State Structure

  The internal state is a tuple `{added_set, removed_set}` where both
  are MapSets containing the respective elements.

  ## Conflict Resolution

  - Add wins over non-existence (element is added if not removed)
  - Remove wins permanently (element cannot be re-added)
  - Final value = added_set - removed_set

  ## Examples

      # Create new set
      set = TPSet_OB.new()

      # Add an element
      {:ok, add_effect} = TPSet_OB.downstream({:add, "item"}, set)
      {:ok, new_set} = TPSet_OB.update(add_effect, set)

      # Remove the element
      {:ok, remove_effect} = TPSet_OB.downstream({:remove, "item"}, new_set)
      {:ok, final_set} = TPSet_OB.update(remove_effect, new_set)

      # Try to re-add (will fail)
      {:error, _} = TPSet_OB.downstream({:add, "item"}, final_set)
  """

  @type t :: :tpset_ob
  @type element :: term()
  @type state :: {MapSet.t(element()), MapSet.t(element())}
  @type operation ::
          {:add, element()}
          | {:add_all, [element()]}
          | {:remove, element()}
          | {:remove_all, [element()]}
  @type effect ::
          {:add_elem, element()}
          | {:add_elems, [element()]}
          | {:remove_elem, element()}
          | {:remove_elems, [element()]}

  @doc """
  Creates a new Two-Phase Set with empty state.

  ## Returns

  Empty set state with both added and removed sets empty.

  ## Examples

      set = TPSet_OB.new()
      MapSet.new() == TPSet_OB.value(set)
  """
  @spec new() :: state()
  def new() do
    # Two-phase set consists of two sets: added and removed (tombstones)
    {MapSet.new(), MapSet.new()}
  end

  @doc """
  Extracts the current value of the Two-Phase Set.

  Returns the set difference: elements that have been added minus
  elements that have been removed (tombstones).

  ## Parameters

  - `{added, removed}`: Current set state

  ## Returns

  MapSet containing all elements currently in the set.

  ## Examples

      state = {MapSet.new(["a", "b"]), MapSet.new(["b"])}
      MapSet.new(["a"]) == TPSet_OB.value(state)
  """
  @spec value(state()) :: MapSet.t(element())
  def value({added, removed}) do
    # The value is the set difference: added - removed
    MapSet.difference(added, removed)
  end

  @doc """
  Generates a downstream effect for adding a single element.

  Validates that the element has not been previously removed before
  allowing the add operation.

  ## Parameters

  - `{:add, elem}`: Add operation for element
  - `{_added, removed}`: Current set state (only removed set is checked)

  ## Returns

  - `{:ok, {:add_elem, element}}`: Effect ready for broadcast
  - `{:error, reason}`: If element was previously removed

  ## Examples

      {:ok, {:add_elem, "item"}} = TPSet_OB.downstream({:add, "item"}, set)
  """
  @spec downstream({:add, element()}, state()) ::
          {:ok, {:add_elem, element()}} | {:error, String.t()}
  def downstream({:add, elem}, {_added, removed}) do
    # Can only add if element hasn't been removed (no tombstone)
    if MapSet.member?(removed, elem) do
      {:error, "Cannot re-add removed element"}
    else
      {:ok, {:add_elem, elem}}
    end
  end

  @spec downstream({:add_all, [element()]}, state()) :: {:ok, {:add_elems, [element()]}}
  def downstream({:add_all, elems}, {_added, removed}) do
    # Filter out any elements that have been removed
    valid_elems = Enum.reject(elems, &MapSet.member?(removed, &1))
    {:ok, {:add_elems, valid_elems}}
  end

  @spec downstream({:remove, element()}, state()) ::
          {:ok, {:remove_elem, element()}} | {:error, String.t()}
  def downstream({:remove, elem}, {added, _removed}) do
    # Can only remove if element exists in added set
    if MapSet.member?(added, elem) do
      {:ok, {:remove_elem, elem}}
    else
      {:error, "Cannot remove non-existent element"}
    end
  end

  @spec downstream({:remove_all, [element()]}, state()) :: {:ok, {:remove_elems, [element()]}}
  def downstream({:remove_all, elems}, {added, _removed}) do
    # Filter to only remove elements that exist
    valid_removals = Enum.filter(elems, &MapSet.member?(added, &1))
    {:ok, {:remove_elems, valid_removals}}
  end

  @doc """
  Applies an add_elem effect to the set state.

  Adds the element to the added set.

  ## Parameters

  - `{:add_elem, elem}`: Effect to apply
  - `{added, removed}`: Current set state

  ## Returns

  - `{:ok, new_state}`: Updated set state

  ## Examples

      {:ok, new_state} = TPSet_OB.update({:add_elem, "item"}, state)
  """
  @spec update({:add_elem, element()}, state()) :: {:ok, state()}
  def update({:add_elem, elem}, {added, removed}) do
    {:ok, {MapSet.put(added, elem), removed}}
  end

  @spec update({:add_elems, [element()]}, state()) :: {:ok, state()}
  def update({:add_elems, elems}, {added, removed}) do
    new_added = Enum.reduce(elems, added, &MapSet.put(&2, &1))
    {:ok, {new_added, removed}}
  end

  @spec update({:remove_elem, element()}, state()) :: {:ok, state()}
  def update({:remove_elem, elem}, {added, removed}) do
    {:ok, {added, MapSet.put(removed, elem)}}
  end

  @spec update({:remove_elems, [element()]}, state()) :: {:ok, state()}
  def update({:remove_elems, elems}, {added, removed}) do
    new_removed = Enum.reduce(elems, removed, &MapSet.put(&2, &1))
    {:ok, {added, new_removed}}
  end

  @doc """
  Checks if two Two-Phase Set states are equal.

  Compares both the added and removed sets for equality.

  ## Parameters

  - `{added1, removed1}`: First set state
  - `{added2, removed2}`: Second set state

  ## Returns

  Boolean indicating if the states are equal.

  ## Examples

      true = TPSet_OB.equal(state, state)
      false = TPSet_OB.equal(state1, state2)
  """
  @spec equal(state(), state()) :: boolean()
  def equal({added1, removed1}, {added2, removed2}) do
    MapSet.equal?(added1, added2) and MapSet.equal?(removed1, removed2)
  end

  @doc """
  Indicates whether generating downstream effects requires the current state.

  All TPSet operations require state to check preconditions:
  - Add operations need to check if elements are in removed set
  - Remove operations need to check if elements are in added set

  ## Parameters

  - `operation`: The operation to check

  ## Returns

  Always `true` - all operations require state.

  ## Examples

      true = TPSet_OB.require_state_downstream({:add, "item"})
      true = TPSet_OB.require_state_downstream({:remove, "item"})
  """
  @spec require_state_downstream(operation()) :: boolean()
  def require_state_downstream({:add, _}) do
    true
  end

  def require_state_downstream({:add_all, _}) do
    true
  end

  def require_state_downstream({:remove, _}) do
    true
  end

  def require_state_downstream({:remove_all, _}) do
    true
  end
end
