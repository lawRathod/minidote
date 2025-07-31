defmodule CRDT do
  @moduledoc """
  Behavior module defining the CRDT (Conflict-free Replicated Data Type) interface.

  This module establishes the contract that all CRDT implementations must follow,
  providing a uniform API for different CRDT types in the Minidote system.

  ## CRDT Types

  CRDTs are data structures that can be replicated across multiple nodes in a 
  distributed system and can be updated independently without coordination.
  They guarantee eventual consistency - all replicas converge to the same state.

  ### Naming Convention

  CRDT modules follow the pattern: `<Type>_<Semantics>_<Implementation>`
  - **Type**: The data structure (Counter, Set, Register, Flag)
  - **Semantics**: Conflict resolution strategy (PN, AW, EW, etc.)
  - **Implementation**: Operation-based (OB) or State-based (SB)

  ### Available CRDTs

  - `Counter_PN_OB`: Positive-Negative Counter (operation-based)
  - `Counter_PN_SB`: Positive-Negative Counter (state-based)
  - `Set_AW_OB`: Add-Wins Set (operation-based)
  - `MVReg_OB`: Multi-Value Register (operation-based)
  - `TPSet_OB`: Two-Phase Set (operation-based) 
  - `Flag_EW_OB`: Enable-Wins Flag (operation-based)

  ## Operation-based vs State-based

  - **Operation-based (OB)**: Broadcasts operations/effects to other nodes
  - **State-based (SB)**: Periodically synchronizes entire state between nodes

  ## Core Concepts

  - **Downstream Effects**: Operations transformed for network broadcast
  - **Causal Delivery**: Effects applied in causal order
  - **Conflict Resolution**: Automatic and deterministic resolution of concurrent updates
  - **Convergence**: All replicas eventually reach the same state

  ## Example

      # Create a new counter
      counter = Counter_PN_OB.new()
      
      # Generate a downstream effect for increment
      {:ok, effect} = Counter_PN_OB.downstream(:increment, counter)
      
      # Apply the effect to get new state
      {:ok, new_counter} = Counter_PN_OB.update(effect, counter)
      
      # Get the current value
      value = Counter_PN_OB.value(new_counter)
  """

  @type t ::
          Set_AW_OB.t()
          | Counter_PN_OB.t()
          | MVReg_OB.t()
          | TPSet_OB.t()
          | Counter_PN_SB.t()
          | Flag_EW_OB.t()

  @type crdt :: t()
  @type update :: {atom(), term()} | atom()
  @type effect :: term()
  @type value :: term()
  @type reason :: term()
  @type internal_crdt :: term()
  @type internal_effect :: term()

  @doc """
  Creates a new instance of the CRDT with initial state.

  ## Returns

  The initial internal state of the CRDT.
  """
  @callback new() :: internal_crdt()

  @doc """
  Extracts the semantic value from the CRDT's internal state.

  ## Parameters

  - `internal_value`: The internal CRDT state

  ## Returns

  The semantic value that applications can use.
  """
  @callback value(internal_value :: internal_crdt()) :: value()

  @doc """
  Generates a downstream effect from an update operation.

  In operation-based CRDTs, this transforms user operations into effects
  that can be broadcast to other replicas.

  ## Parameters

  - `update`: The update operation to perform
  - `state`: Current internal CRDT state

  ## Returns

  - `{:ok, effect}`: Effect ready for broadcast
  - `{:error, reason}`: Operation failed validation
  """
  @callback downstream(update(), internal_crdt()) :: {:ok, internal_effect()} | {:error, reason()}

  @doc """
  Applies a downstream effect to the CRDT state.

  ## Parameters

  - `effect`: The effect to apply (from downstream/2)
  - `state`: Current internal CRDT state

  ## Returns

  - `{:ok, new_state}`: Updated CRDT state
  """
  @callback update(internal_effect(), internal_crdt()) :: {:ok, internal_crdt()}

  @doc """
  Indicates whether an operation requires the current state to generate its effect.

  This is an optimization hint - some operations can generate their effect
  without knowing the current state, enabling more efficient processing.

  ## Parameters

  - `update`: The update operation to check

  ## Returns

  Boolean indicating if current state is required.
  """
  @callback require_state_downstream(update :: update()) :: boolean()

  @doc """
  Checks if two CRDT states are semantically equal.

  ## Parameters

  - `state1`: First CRDT state to compare
  - `state2`: Second CRDT state to compare

  ## Returns

  Boolean indicating if states are equal.
  """
  @callback equal(internal_crdt(), internal_crdt()) :: boolean()

  @doc """
  Merges two CRDT states (for state-based CRDTs only).

  This callback is optional and only implemented by state-based CRDTs.
  It performs the merge operation that ensures convergence.

  ## Parameters

  - `state1`: First CRDT state to merge
  - `state2`: Second CRDT state to merge

  ## Returns

  Merged CRDT state that incorporates both input states.
  """
  @optional_callbacks merge: 2
  @callback merge(internal_crdt(), internal_crdt()) :: internal_crdt()

  @doc """
  Guard to check if a module is a valid CRDT type.

  Used to validate CRDT types at compile time.
  """
  defguard valid?(type)
           when type == Set_AW_OB or
                  type == Counter_PN_OB or
                  type == MVReg_OB or
                  type == TPSet_OB or
                  type == Counter_PN_SB or
                  type == Flag_EW_OB

  @doc """
  Creates a new CRDT instance of the specified type.

  ## Parameters

  - `type`: The CRDT module (must be a valid CRDT type)

  ## Returns

  Initial CRDT state.

  ## Examples

      counter = CRDT.new(Counter_PN_OB)
      set = CRDT.new(Set_AW_OB)
  """
  @spec new(module()) :: internal_crdt()
  def new(type) when valid?(type) do
    type.new()
  end

  @doc """
  Extracts the semantic value from a CRDT state.

  ## Parameters

  - `type`: The CRDT module
  - `state`: The CRDT's internal state

  ## Returns

  The semantic value of the CRDT.

  ## Examples

      value = CRDT.value(Counter_PN_OB, counter_state)
      items = CRDT.value(Set_AW_OB, set_state)
  """
  @spec value(module(), internal_crdt()) :: value()
  def value(type, state) do
    type.value(state)
  end

  @doc """
  Generates a downstream effect for an operation.

  ## Parameters

  - `type`: The CRDT module
  - `update`: The operation to perform
  - `state`: Current CRDT state

  ## Returns

  - `{:ok, effect}`: Effect ready for broadcast
  - `{:error, reason}`: Operation validation failed

  ## Examples

      {:ok, effect} = CRDT.downstream(Counter_PN_OB, :increment, counter)
      {:ok, effect} = CRDT.downstream(Set_AW_OB, {:add, "item"}, set)
  """
  @spec downstream(module(), update(), internal_crdt()) ::
          {:ok, internal_effect()} | {:error, reason()}
  def downstream(type, update, state) do
    type.downstream(update, state)
  end

  @doc """
  Applies a downstream effect to a CRDT state.

  ## Parameters

  - `type`: The CRDT module
  - `effect`: The effect to apply
  - `state`: Current CRDT state

  ## Returns

  - `{:ok, new_state}`: Updated CRDT state

  ## Examples

      {:ok, new_counter} = CRDT.update(Counter_PN_OB, effect, counter)
      {:ok, new_set} = CRDT.update(Set_AW_OB, effect, set)
  """
  @spec update(module(), internal_effect(), internal_crdt()) :: {:ok, internal_crdt()}
  def update(type, effect, state) do
    type.update(effect, state)
  end

  @doc """
  Checks if an operation requires current state to generate its effect.

  ## Parameters

  - `type`: The CRDT module
  - `update`: The operation to check

  ## Returns

  Boolean indicating if state is required.

  ## Examples

      needs_state = CRDT.require_state_downstream(Counter_PN_OB, :increment)
      needs_state = CRDT.require_state_downstream(Set_AW_OB, {:add, "item"})
  """
  @spec require_state_downstream(module(), update()) :: boolean()
  def require_state_downstream(type, update) do
    type.require_state_downstream(update)
  end

  @doc """
  Merges two CRDT states (for state-based CRDTs only).

  This function is only applicable to state-based CRDTs that implement
  the merge/2 callback.

  ## Parameters

  - `type`: The CRDT module (must implement merge/2)
  - `state1`: First CRDT state
  - `state2`: Second CRDT state

  ## Returns

  Merged CRDT state.

  ## Raises

  `RuntimeError` if the CRDT type doesn't support merge operations.

  ## Examples

      merged = CRDT.merge(Counter_PN_SB, counter1, counter2)
  """
  @spec merge(module(), internal_crdt(), internal_crdt()) :: internal_crdt()
  def merge(type, state1, state2) do
    if function_exported?(type, :merge, 2) do
      type.merge(state1, state2)
    else
      raise "CRDT type #{inspect(type)} does not support merge operation"
    end
  end

  @doc """
  Serializes a CRDT state to binary format.

  Useful for persisting CRDT states or transmitting them over the network.

  ## Parameters

  - `term`: The CRDT state to serialize

  ## Returns

  Binary representation of the CRDT state.

  ## Examples

      binary = CRDT.to_binary(counter_state)
  """
  @spec to_binary(internal_crdt()) :: binary()
  def to_binary(term) do
    :erlang.term_to_binary(term)
  end

  @doc """
  Deserializes a CRDT state from binary format.

  ## Parameters

  - `binary`: Binary data to deserialize

  ## Returns

  The deserialized CRDT state.

  ## Examples

      counter_state = CRDT.from_binary(binary_data)
  """
  @spec from_binary(binary()) :: internal_crdt()
  def from_binary(binary) do
    :erlang.binary_to_term(binary)
  end
end
