defmodule Flag_EW_OB do
  @behaviour CRDT

  @moduledoc """
  Operation-based Enable-Wins Flag CRDT.

  An Enable-Wins Flag is a CRDT that represents a boolean value with
  enable-wins semantics: when concurrent enable and disable operations
  occur, the enable operation takes precedence. This ensures deterministic
  conflict resolution while allowing concurrent modifications.

  ## Features

  - **Enable Operation**: Set the flag to true
  - **Disable Operation**: Set the flag to false (disables existing enables)
  - **Enable-Wins Semantics**: Concurrent enable/disable operations favor enable
  - **Token-Based**: Uses unique tokens to track enable/disable operations
  - **Convergence**: All replicas converge to the same flag value

  ## Operations

  - `:enable` or `{:enable, _}` - Enable the flag
  - `:disable` or `{:disable, _}` - Disable the flag

  ## State Structure

  The internal state is a tuple `{enable_tokens, disable_tokens}` where:
  - `enable_tokens` is a MapSet of tokens for enable operations
  - `disable_tokens` is a MapSet of tokens that have been disabled

  ## Conflict Resolution

  The flag is enabled if there are any enable tokens that are not in
  the disable tokens set: `not MapSet.subset?(enable_tokens, disable_tokens)`

  This implements enable-wins semantics where:
  - Enable operations create new unique tokens
  - Disable operations disable all current enable tokens
  - New enables after a disable will re-enable the flag

  ## Examples

      # Create new flag
      flag = Flag_EW_OB.new()
      
      # Enable the flag
      {:ok, enable_effect} = Flag_EW_OB.downstream(:enable, flag)
      {:ok, enabled_flag} = Flag_EW_OB.update(enable_effect, flag)
      
      # Check value
      true = Flag_EW_OB.value(enabled_flag)
      
      # Disable the flag
      {:ok, disable_effect} = Flag_EW_OB.downstream(:disable, enabled_flag)
      {:ok, disabled_flag} = Flag_EW_OB.update(disable_effect, enabled_flag)
      
      # Check value
      false = Flag_EW_OB.value(disabled_flag)
  """

  @type t :: :flag_ew_ob
  @type token :: {node(), non_neg_integer()}
  @type state :: {MapSet.t(token()), MapSet.t(token())}
  @type operation :: :enable | :disable | {:enable, term()} | {:disable, term()}
  @type effect :: {:enable_token, token()} | {:disable_tokens, MapSet.t(token())}

  @doc """
  Creates a new Enable-Wins Flag with disabled state.

  ## Returns

  Empty flag state with both enable and disable token sets empty.

  ## Examples

      flag = Flag_EW_OB.new()
      false = Flag_EW_OB.value(flag)
  """
  @spec new() :: state()
  def new() do
    # Flag state: {enable_tokens, disable_tokens}
    {MapSet.new(), MapSet.new()}
  end

  @doc """
  Extracts the current boolean value of the flag.

  The flag is enabled if there are any enable tokens that have not
  been disabled (enable-wins semantics).

  ## Parameters

  - `{enable_tokens, disable_tokens}`: Current flag state

  ## Returns

  Boolean value of the flag.

  ## Examples

      state = {MapSet.new([token1]), MapSet.new()}
      true = Flag_EW_OB.value(state)
  """
  @spec value(state()) :: boolean()
  def value({enable_tokens, disable_tokens}) do
    # Flag is enabled if there are any enable tokens not in disable tokens
    not MapSet.subset?(enable_tokens, disable_tokens)
  end

  @doc """
  Generates downstream effects for flag operations.

  Creates effects for enable/disable operations. Enable operations generate
  unique tokens, while disable operations collect current enable tokens to disable.

  ## Parameters

  - `{:enable, _}` or `:enable`: Enable operation (argument ignored)
  - `{:disable, _}` or `:disable`: Disable operation (argument ignored)
  - `state`: Current flag state (only needed for disable operations)

  ## Returns

  - `{:ok, {:enable_token, token}}`: For enable operations
  - `{:ok, {:disable_tokens, tokens}}`: For disable operations

  ## Examples

      {:ok, {:enable_token, token}} = Flag_EW_OB.downstream(:enable, flag)
      {:ok, {:disable_tokens, tokens}} = Flag_EW_OB.downstream(:disable, flag)
  """
  @spec downstream({:enable, term()}, state()) :: {:ok, {:enable_token, token()}}
  @spec downstream({:disable, term()}, state()) :: {:ok, {:disable_tokens, MapSet.t(token())}}
  @spec downstream(:enable, state()) :: {:ok, {:enable_token, token()}}
  @spec downstream(:disable, state()) :: {:ok, {:disable_tokens, MapSet.t(token())}}
  def downstream({:enable, _}, _state) do
    # Generate unique token for this enable operation
    token = generate_token()
    {:ok, {:enable_token, token}}
  end

  def downstream({:disable, _}, {enable_tokens, _disable_tokens}) do
    # Disable all current enable tokens
    {:ok, {:disable_tokens, enable_tokens}}
  end

  def downstream(:enable, state) do
    downstream({:enable, nil}, state)
  end

  def downstream(:disable, state) do
    downstream({:disable, nil}, state)
  end

  @doc """
  Applies effects to the flag state.

  Updates the flag state by applying enable or disable effects:
  - Enable effects add tokens to the enable tokens set
  - Disable effects add tokens to the disable tokens set

  ## Parameters

  - `{:enable_token, token}`: Add enable token to enable set
  - `{:disable_tokens, tokens}`: Add tokens to disable set  
  - `state`: Current flag state

  ## Returns

  - `{:ok, new_state}`: Updated flag state

  ## Examples

      {:ok, new_state} = Flag_EW_OB.update({:enable_token, token}, state)
      {:ok, new_state} = Flag_EW_OB.update({:disable_tokens, tokens}, state)
  """
  @spec update({:enable_token, token()}, state()) :: {:ok, state()}
  @spec update({:disable_tokens, MapSet.t(token())}, state()) :: {:ok, state()}
  def update({:enable_token, token}, {enable_tokens, disable_tokens}) do
    new_enable_tokens = MapSet.put(enable_tokens, token)
    {:ok, {new_enable_tokens, disable_tokens}}
  end

  def update({:disable_tokens, tokens_to_disable}, {enable_tokens, disable_tokens}) do
    new_disable_tokens = MapSet.union(disable_tokens, tokens_to_disable)
    {:ok, {enable_tokens, new_disable_tokens}}
  end

  @doc """
  Checks if two flag states are equal.

  Compares both enable and disable token sets for equality.

  ## Parameters

  - `{enable1, disable1}`: First flag state
  - `{enable2, disable2}`: Second flag state

  ## Returns

  Boolean indicating if the states are equal.

  ## Examples

      true = Flag_EW_OB.equal(state, state)
      false = Flag_EW_OB.equal(state1, state2)
  """
  @spec equal(state(), state()) :: boolean()
  def equal({enable1, disable1}, {enable2, disable2}) do
    MapSet.equal?(enable1, enable2) and MapSet.equal?(disable1, disable2)
  end

  @doc """
  Indicates whether generating downstream effects requires the current state.

  Enable operations don't need state (generate unique tokens independently).
  Disable operations need state (must know current enable tokens to disable).

  ## Parameters

  - `operation`: The operation to check

  ## Returns

  Boolean indicating if state is required.

  ## Examples

      false = Flag_EW_OB.require_state_downstream(:enable)
      true = Flag_EW_OB.require_state_downstream(:disable)
  """
  @spec require_state_downstream(operation()) :: boolean()
  def require_state_downstream({:enable, _}) do
    false
  end

  def require_state_downstream(:enable) do
    false
  end

  def require_state_downstream({:disable, _}) do
    true
  end

  def require_state_downstream(:disable) do
    true
  end

  # Helper to generate unique tokens
  # Uses current node and timestamp for uniqueness
  @spec generate_token() :: token()
  defp generate_token() do
    {node(), :erlang.system_time(:nanosecond)}
  end
end
