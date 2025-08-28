defmodule MVReg_OB do
  @behaviour CRDT

  @moduledoc """
  Operation-based Multi-Value Register CRDT.

  A Multi-Value Register (MVReg) is a CRDT that can hold multiple concurrent 
  values when writes happen concurrently. Unlike a simple register that would
  lose values in concurrent scenarios, MVReg preserves all values and allows
  the application to decide how to resolve conflicts.

  ## Features

  - **Concurrent Writes**: Preserves all values written concurrently
  - **Causal Ordering**: Uses version vectors to track causality  
  - **Conflict Resolution**: Application-level resolution of multiple values
  - **Assign Operation**: Write new values to the register

  ## Operations

  - `{:assign, value}` - Write a new value to the register

  ## State Structure

  The internal state is a list of `{value, versions}` tuples where:
  - `value` is the stored value
  - `versions` is a MapSet of version tuples `{node, counter}`

  ## Conflict Resolution

  When concurrent writes occur, all values are preserved in the register.
  The application can read all concurrent values and decide how to resolve
  the conflict (e.g., pick latest timestamp, merge values, user choice).

  ## Examples

      # Create new register
      reg = MVReg_OB.new()
      
      # Assign a value
      {:ok, effect} = MVReg_OB.downstream({:assign, "value1"}, reg)
      {:ok, new_reg} = MVReg_OB.update(effect, reg)
      
      # Get current values
      ["value1"] = MVReg_OB.value(new_reg)
  """

  @type t :: :mvreg_ob
  @type version :: {node(), non_neg_integer()}
  @type state :: [{term(), MapSet.t(version())}]
  @type operation :: {:assign, term()}
  @type effect :: {:write, term(), version(), MapSet.t(version())}

  @doc """
  Creates a new Multi-Value Register with empty state.

  ## Returns

  Empty register state (empty list).

  ## Examples

      reg = MVReg_OB.new()
      [] = MVReg_OB.value(reg)
  """
  @spec new() :: state()
  def new() do
    # Empty register has no values
    []
  end

  @doc """
  Extracts all current values from the register.

  Returns all concurrent values without version information.
  The application is responsible for resolving conflicts when
  multiple values are present.

  ## Parameters

  - `state`: Current register state

  ## Returns

  List of all unique values currently in the register.

  ## Examples

      state = [{"value1", versions1}, {"value2", versions2}]
      ["value1", "value2"] = MVReg_OB.value(state)
  """
  @spec value(state()) :: [term()]
  def value(state) do
    # Return all concurrent values (the application decides how to resolve)
    # Extract just the values without version information
    state
    |> Enum.map(fn {val, _versions} -> val end)
    |> Enum.uniq()
  end

  @doc """
  Generates a downstream effect for assigning a new value.

  Creates a write effect that includes a unique version and all
  existing versions that will be overwritten by this assignment.

  ## Parameters

  - `{:assign, new_value}`: Assign operation with new value
  - `state`: Current register state (required to determine versions to overwrite)

  ## Returns

  - `{:ok, {:write, value, version, versions_to_overwrite}}`: Effect ready for broadcast

  ## Examples

      {:ok, {:write, "new_value", version, old_versions}} = 
        MVReg_OB.downstream({:assign, "new_value"}, reg)
  """
  @spec downstream({:assign, term()}, state()) :: {:ok, effect()}
  def downstream({:assign, new_value}, state) do
    # Generate new version for this write
    version = generate_version()

    # Collect all versions from current state to overwrite
    versions_to_overwrite =
      state
      |> Enum.flat_map(fn {_val, versions} -> MapSet.to_list(versions) end)
      |> MapSet.new()

    {:ok, {:write, new_value, version, versions_to_overwrite}}
  end

  @doc """
  Applies a write effect to the register state.

  Removes values whose versions are being overwritten and adds
  the new value with its version. If the same value already exists
  with other versions, the new version is added to it.

  ## Parameters

  - `{:write, new_value, version, versions_to_overwrite}`: Effect to apply
  - `state`: Current register state

  ## Returns

  - `{:ok, new_state}`: Updated register state

  ## Examples

      effect = {:write, "value", version, old_versions}
      {:ok, new_state} = MVReg_OB.update(effect, old_state)
  """
  @spec update(effect(), state()) :: {:ok, state()}
  def update({:write, new_value, version, versions_to_overwrite}, state) do
    # Remove all values whose versions are in versions_to_overwrite
    filtered_state =
      state
      |> Enum.filter(fn {_val, versions} ->
        # Keep values that have at least one version not being overwritten
        not MapSet.subset?(versions, versions_to_overwrite)
      end)
      |> Enum.map(fn {val, versions} ->
        # Remove overwritten versions from remaining values
        {val, MapSet.difference(versions, versions_to_overwrite)}
      end)
      |> Enum.filter(fn {_val, versions} ->
        # Only keep values with remaining versions
        not Enum.empty?(versions)
      end)

    # Add or update the new value
    new_version_set = MapSet.new([version])

    updated_state =
      case Enum.find_index(filtered_state, fn {val, _} -> val == new_value end) do
        nil ->
          # New value, add it
          filtered_state ++ [{new_value, new_version_set}]

        index ->
          # Value exists, add version to it
          {val, existing_versions} = Enum.at(filtered_state, index)
          updated_versions = MapSet.union(existing_versions, new_version_set)
          List.replace_at(filtered_state, index, {val, updated_versions})
      end

    {:ok, updated_state}
  end

  @doc """
  Checks if two register states are equal.

  Compares states by sorting them by value to handle different orderings.

  ## Parameters

  - `state1`: First register state
  - `state2`: Second register state

  ## Returns

  Boolean indicating if the states are equal.

  ## Examples

      true = MVReg_OB.equal(state, state)
      false = MVReg_OB.equal(state1, state2)
  """
  @spec equal(state(), state()) :: boolean()
  def equal(state1, state2) do
    # Sort by value for comparison
    sort_state = fn state ->
      Enum.sort_by(state, fn {val, _} -> val end)
    end

    sort_state.(state1) == sort_state.(state2)
  end

  @doc """
  Indicates whether generating downstream effects requires the current state.

  MVReg requires state to determine which versions to overwrite when assigning.

  ## Parameters

  - `{:assign, _}`: The assign operation

  ## Returns

  Always `true` - state is required for MVReg operations.

  ## Examples

      true = MVReg_OB.require_state_downstream({:assign, "value"})
  """
  @spec require_state_downstream(operation()) :: boolean()
  def require_state_downstream({:assign, _}) do
    true
  end

  # Helper function to generate unique version identifiers
  # Uses the current node and a monotonic integer to ensure uniqueness
  @spec generate_version() :: version()
  defp generate_version() do
    {node(), :erlang.unique_integer([:positive, :monotonic])}
  end
end
