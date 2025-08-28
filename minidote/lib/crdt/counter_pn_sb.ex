defmodule Counter_PN_SB do
  @behaviour CRDT

  @moduledoc """
  State-based Positive-Negative Counter CRDT.

  A state-based PN-Counter that maintains separate positive and negative 
  counters per node. Unlike operation-based CRDTs, state-based CRDTs 
  synchronize by exchanging and merging entire states rather than operations.

  ## Features

  - **Per-node Counters**: Maintains separate increment/decrement counters for each node
  - **State Merging**: Convergence achieved by merging states (taking maximum values)
  - **Increment/Decrement**: Supports both increment and decrement operations
  - **Monotonic**: Individual node counters only increase (ensuring convergence)

  ## State Structure

  The internal state contains:
  - `positive`: Map of node → positive increment count
  - `negative`: Map of node → negative increment count

  Final value = sum(positive) - sum(negative)

  ## Operations

  - `:increment` - Increment by 1
  - `{:increment, n}` - Increment by n (n > 0)
  - `:decrement` - Decrement by 1  
  - `{:decrement, n}` - Decrement by n (n > 0)

  ## Examples

      # Create new counter
      counter = Counter_PN_SB.new()
      
      # Generate and apply increment
      {:ok, effect} = Counter_PN_SB.downstream(:increment, counter)
      {:ok, new_counter} = Counter_PN_SB.update(effect, counter)
      
      # Merge two counter states
      merged = Counter_PN_SB.merge(counter1, counter2)
      
      # Get current value
      1 = Counter_PN_SB.value(new_counter)
  """

  @type t :: :counter_pn_sb
  @type state :: %{
          positive: %{node() => non_neg_integer()},
          negative: %{node() => non_neg_integer()}
        }
  @type operation ::
          :increment | :decrement | {:increment, pos_integer()} | {:decrement, pos_integer()}
  @type effect :: {:increment | :decrement, node(), pos_integer()}

  @doc """
  Creates a new state-based PN-Counter with empty state.

  ## Returns

  Initial counter state with empty positive and negative maps.

  ## Examples

      counter = Counter_PN_SB.new()
      0 = Counter_PN_SB.value(counter)
  """
  @spec new() :: state()
  def new() do
    %{positive: %{}, negative: %{}}
  end

  @doc """
  Calculates the current value of the counter.

  The value is computed as the sum of all positive increments minus
  the sum of all negative increments across all nodes.

  ## Parameters

  - `state`: Current counter state

  ## Returns

  The integer value of the counter.

  ## Examples

      state = %{positive: %{node1: 5, node2: 3}, negative: %{node1: 2}}
      6 = Counter_PN_SB.value(state)  # (5 + 3) - 2 = 6
  """
  @spec value(state()) :: integer()
  def value(%{positive: pos, negative: neg}) do
    pos_sum = pos |> Map.values() |> Enum.sum()
    neg_sum = neg |> Map.values() |> Enum.sum()
    pos_sum - neg_sum
  end

  @doc """
  Merges two counter states by taking the maximum value for each node.

  This is the core convergence operation for state-based CRDTs. Each node's
  counter values are merged by taking the maximum, ensuring monotonicity
  and eventual consistency.

  ## Parameters

  - `state1`: First counter state
  - `state2`: Second counter state

  ## Returns

  Merged counter state.

  ## Examples

      state1 = %{positive: %{node1: 5}, negative: %{node1: 2}}
      state2 = %{positive: %{node1: 3, node2: 4}, negative: %{node2: 1}}
      merged = Counter_PN_SB.merge(state1, state2)
      # Result: %{positive: %{node1: 5, node2: 4}, negative: %{node1: 2, node2: 1}}
  """
  @spec merge(state(), state()) :: state()
  def merge(state1, state2) do
    %{
      positive: merge_counters(state1.positive, state2.positive),
      negative: merge_counters(state1.negative, state2.negative)
    }
  end

  @doc """
  Generates a downstream effect for a counter operation.

  Creates effects that include the current node identifier and operation value.
  These effects can be applied locally or sent to other replicas.

  ## Parameters

  - `operation`: The operation to perform
  - `_state`: Current counter state (unused)

  ## Returns

  - `{:ok, effect}`: Effect tuple containing operation type, node, and value

  ## Examples

      {:ok, {:increment, node(), 1}} = Counter_PN_SB.downstream(:increment, counter)
      {:ok, {:decrement, node(), 5}} = Counter_PN_SB.downstream({:decrement, 5}, counter)
  """
  @spec downstream(operation(), state()) :: {:ok, effect()}
  def downstream(:increment, _state) do
    {:ok, {:increment, node(), 1}}
  end

  def downstream(:decrement, _state) do
    {:ok, {:decrement, node(), 1}}
  end

  def downstream({:increment, by}, _state) when is_integer(by) and by > 0 do
    {:ok, {:increment, node(), by}}
  end

  def downstream({:decrement, by}, _state) when is_integer(by) and by > 0 do
    {:ok, {:decrement, node(), by}}
  end

  @doc """
  Applies a downstream effect to the counter state.

  Updates the appropriate node's counter (positive for increments,
  negative for decrements) by adding the effect value.

  ## Parameters

  - `effect`: The effect to apply
  - `state`: Current counter state

  ## Returns

  - `{:ok, new_state}`: Updated counter state

  ## Examples

      effect = {:increment, :node1, 5}
      {:ok, new_state} = Counter_PN_SB.update(effect, old_state)
  """
  @spec update(effect(), state()) :: {:ok, state()}
  def update({:increment, node, by}, %{positive: pos, negative: neg}) do
    current = Map.get(pos, node, 0)
    new_pos = Map.put(pos, node, current + by)
    {:ok, %{positive: new_pos, negative: neg}}
  end

  def update({:decrement, node, by}, %{positive: pos, negative: neg}) do
    current = Map.get(neg, node, 0)
    new_neg = Map.put(neg, node, current + by)
    {:ok, %{positive: pos, negative: new_neg}}
  end

  @doc """
  Checks if two counter states are equal.

  ## Parameters

  - `state1`: First counter state
  - `state2`: Second counter state

  ## Returns

  Boolean indicating if the states are equal.

  ## Examples

      true = Counter_PN_SB.equal(state, state)
      false = Counter_PN_SB.equal(state1, state2)
  """
  @spec equal(state(), state()) :: boolean()
  def equal(state1, state2) do
    state1 == state2
  end

  @doc """
  Indicates whether generating downstream effects requires the current state.

  For state-based PN-Counter, effects can be generated without the current state.

  ## Parameters

  - `_operation`: The operation (ignored)

  ## Returns

  Always `false` - state is not required.

  ## Examples

      false = Counter_PN_SB.require_state_downstream(:increment)
  """
  @spec require_state_downstream(operation()) :: boolean()
  def require_state_downstream(_) do
    false
  end

  # Helper function to merge counter maps (take max for each node)
  @spec merge_counters(map(), map()) :: map()
  defp merge_counters(map1, map2) do
    all_keys = MapSet.union(MapSet.new(Map.keys(map1)), MapSet.new(Map.keys(map2)))

    Enum.reduce(all_keys, %{}, fn key, acc ->
      val1 = Map.get(map1, key, 0)
      val2 = Map.get(map2, key, 0)
      Map.put(acc, key, max(val1, val2))
    end)
  end
end
