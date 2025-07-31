defmodule Counter_PN_OB do
  @behaviour CRDT

  @moduledoc """
  Operation-based Positive-Negative Counter CRDT.

  A PN-Counter (Positive-Negative Counter) is a CRDT that supports both
  increment and decrement operations. The operation-based version broadcasts
  increment/decrement effects to achieve convergence across replicas.

  ## Features

  - **Increment**: Add positive values to the counter
  - **Decrement**: Subtract values from the counter  
  - **Convergence**: All replicas converge to the same value
  - **Commutativity**: Operations can be applied in any order

  ## Operations

  - `:increment` - Increment by 1
  - `{:increment, n}` - Increment by n
  - `:decrement` - Decrement by 1
  - `{:decrement, n}` - Decrement by n

  ## Examples

      # Create new counter
      counter = Counter_PN_OB.new()
      
      # Generate increment effect
      {:ok, inc_effect} = Counter_PN_OB.downstream(:increment, counter)
      
      # Apply effect
      {:ok, new_counter} = Counter_PN_OB.update(inc_effect, counter)
      
      # Get current value  
      1 = Counter_PN_OB.value(new_counter)
  """

  @type t :: :counter_pn_ob
  @type state :: integer()
  @type operation :: :increment | :decrement | {:increment, integer()} | {:decrement, integer()}
  @type effect :: integer()

  @doc """
  Creates a new PN-Counter with initial value of 0.

  ## Returns

  Initial counter state (0).

  ## Examples

      counter = Counter_PN_OB.new()
      0 = Counter_PN_OB.value(counter)
  """
  @spec new() :: state()
  def new() do
    0
  end

  @doc """
  Extracts the current value of the counter.

  ## Parameters

  - `pn_state`: Current counter state

  ## Returns

  The integer value of the counter.

  ## Examples

      5 = Counter_PN_OB.value(5)
  """
  @spec value(state()) :: integer()
  def value(pn_state) when is_integer(pn_state) do
    pn_state
  end

  @doc """
  Generates a downstream effect for a counter operation.

  Transforms user operations into effects that can be broadcast to other
  replicas. The counter state is not needed for generating effects.

  ## Parameters

  - `operation`: The operation to perform (see module doc for options)
  - `_state`: Current counter state (unused for this CRDT)

  ## Returns

  - `{:ok, effect}`: Effect ready for broadcast (positive for increment, negative for decrement)

  ## Examples

      {:ok, 1} = Counter_PN_OB.downstream(:increment, counter)
      {:ok, -1} = Counter_PN_OB.downstream(:decrement, counter)
      {:ok, 5} = Counter_PN_OB.downstream({:increment, 5}, counter)
      {:ok, -3} = Counter_PN_OB.downstream({:decrement, 3}, counter)
  """
  @spec downstream(operation(), state()) :: {:ok, effect()}
  def downstream(:increment, _) do
    {:ok, 1}
  end

  def downstream(:decrement, _) do
    {:ok, -1}
  end

  def downstream({:increment, by}, _) when is_integer(by) do
    {:ok, by}
  end

  def downstream({:decrement, by}, _) when is_integer(by) do
    {:ok, -by}
  end

  @doc """
  Applies a downstream effect to the counter state.

  Updates the counter by adding the effect value (which may be positive
  for increments or negative for decrements).

  ## Parameters

  - `effect`: The effect to apply (integer value)
  - `pn_state`: Current counter state

  ## Returns

  - `{:ok, new_state}`: Updated counter state

  ## Examples

      {:ok, 6} = Counter_PN_OB.update(5, 1)  # 1 + 5 = 6
      {:ok, 3} = Counter_PN_OB.update(-2, 5) # 5 + (-2) = 3
  """
  @spec update(effect(), state()) :: {:ok, state()}
  def update(effect, pn_state) do
    {:ok, pn_state + effect}
  end

  @doc """
  Checks if two counter states are equal.

  ## Parameters

  - `pn_state1`: First counter state
  - `pn_state2`: Second counter state

  ## Returns

  Boolean indicating if the states are equal.

  ## Examples

      true = Counter_PN_OB.equal(5, 5)
      false = Counter_PN_OB.equal(3, 7)
  """
  @spec equal(state(), state()) :: boolean()
  def equal(pn_state1, pn_state2) do
    pn_state1 === pn_state2
  end

  @doc """
  Indicates whether generating downstream effects requires the current state.

  For PN-Counter, effects can be generated without knowing the current state,
  making this an optimization that returns false.

  ## Parameters

  - `_operation`: The operation (ignored)

  ## Returns

  Always `false` - state is not required.

  ## Examples

      false = Counter_PN_OB.require_state_downstream(:increment)
      false = Counter_PN_OB.require_state_downstream({:decrement, 5})
  """
  @spec require_state_downstream(operation()) :: boolean()
  def require_state_downstream(_) do
    false
  end
end
