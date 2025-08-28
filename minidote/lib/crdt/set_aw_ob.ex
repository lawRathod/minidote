defmodule Set_AW_OB do
  @behaviour CRDT

  @moduledoc """
  Documentation for `Set_AW_OB`.

  An operation-based Observed-Remove Set CRDT.

  Reference papers:
  Marc Shapiro, Nuno Preguiça, Carlos Baquero, Marek Zawirski (2011)
  A comprehensive study of Convergent and Commutative Replicated Data Types
  """

  @type t :: :set_aw_ob
  @type element :: term()
  @type token :: {node(), integer(), reference()}
  @type state :: %{element() => {MapSet.t(token()), MapSet.t(token())}}
  @type operation ::
          {:add, element()}
          | {:add_all, [element()]}
          | {:remove, element()}
          | {:remove_all, [element()]}
          | {:reset, {}}
  @type effect ::
          {:add_token, element(), token()}
          | {:add_tokens, [{element(), token()}]}
          | {:remove_tokens, element(), MapSet.t(token())}
          | {:remove_all_tokens, [{element(), MapSet.t(token())}]}
          | {:reset_tokens, [{element(), MapSet.t(token())}]}

  @doc """
  Creates a new Add-Wins Set with empty state.

  ## Returns

  Empty set state (empty map).

  ## Examples

      set = Set_AW_OB.new()
      MapSet.new() == Set_AW_OB.value(set)
  """
  @spec new() :: state()
  def new() do
    # Set state is a map: element -> {add_tokens, remove_tokens}
    # where tokens are unique identifiers (node + timestamp)
    %{}
  end

  @doc """
  Extracts the current value of the set.

  Returns elements where add_tokens outnumber remove_tokens,
  implementing the add-wins semantics.

  ## Parameters

  - `state`: Current set state

  ## Returns

  MapSet containing all elements currently in the set.

  ## Examples

      state = %{"a" => {MapSet.new([token1, token2]), MapSet.new([token3])}}
      MapSet.new(["a"]) == Set_AW_OB.value(state)
  """
  @spec value(state()) :: MapSet.t(element())
  def value(state) do
    # Return only elements where add_tokens > remove_tokens
    state
    |> Enum.filter(fn {_elem, {add_tokens, remove_tokens}} ->
      MapSet.size(add_tokens) > MapSet.size(remove_tokens)
    end)
    |> Enum.map(fn {elem, _} -> elem end)
    |> MapSet.new()
  end

  @doc """
  Generates a downstream effect for adding a single element.

  Creates a unique token for the add operation to ensure
  proper conflict resolution.

  ## Parameters

  - `{:add, elem}`: Add operation for element
  - `_state`: Current set state (unused)

  ## Returns

  - `{:ok, {:add_token, element, token}}`: Effect ready for broadcast

  ## Examples

      {:ok, {:add_token, "item", token}} = Set_AW_OB.downstream({:add, "item"}, set)
  """
  @spec downstream({:add, element()}, state()) :: {:ok, {:add_token, element(), token()}}
  def downstream({:add, elem}, _state) do
    # Generate unique token for this add operation
    token = generate_token()
    {:ok, {:add_token, elem, token}}
  end

  def downstream({:add_all, elems}, _state) do
    # Generate tokens for multiple elements
    tokens = Enum.map(elems, fn elem -> {elem, generate_token()} end)
    {:ok, {:add_tokens, tokens}}
  end

  def downstream({:remove, elem}, state) do
    # Get current add tokens for this element
    case Map.get(state, elem) do
      nil -> {:ok, {:remove_tokens, elem, MapSet.new()}}
      {add_tokens, _remove_tokens} -> {:ok, {:remove_tokens, elem, add_tokens}}
    end
  end

  def downstream({:remove_all, elems}, state) do
    # Collect all add tokens for elements to remove
    tokens_to_remove =
      Enum.map(elems, fn elem ->
        case Map.get(state, elem) do
          nil -> {elem, MapSet.new()}
          {add_tokens, _} -> {elem, add_tokens}
        end
      end)

    {:ok, {:remove_all_tokens, tokens_to_remove}}
  end

  def downstream({:reset, {}}, state) do
    # Remove all elements by collecting all their add tokens
    all_tokens =
      Enum.map(state, fn {elem, {add_tokens, _}} ->
        {elem, add_tokens}
      end)

    {:ok, {:reset_tokens, all_tokens}}
  end

  def update({:add_token, elem, token}, state) do
    {add_tokens, remove_tokens} = Map.get(state, elem, {MapSet.new(), MapSet.new()})
    new_add_tokens = MapSet.put(add_tokens, token)
    new_state = Map.put(state, elem, {new_add_tokens, remove_tokens})
    {:ok, new_state}
  end

  def update({:add_tokens, tokens}, state) do
    new_state =
      Enum.reduce(tokens, state, fn {elem, token}, acc_state ->
        {add_tokens, remove_tokens} = Map.get(acc_state, elem, {MapSet.new(), MapSet.new()})
        new_add_tokens = MapSet.put(add_tokens, token)
        Map.put(acc_state, elem, {new_add_tokens, remove_tokens})
      end)

    {:ok, new_state}
  end

  def update({:remove_tokens, elem, tokens_to_remove}, state) do
    case Map.get(state, elem) do
      nil ->
        {:ok, state}

      {add_tokens, remove_tokens} ->
        new_remove_tokens = MapSet.union(remove_tokens, tokens_to_remove)
        new_state = Map.put(state, elem, {add_tokens, new_remove_tokens})
        {:ok, new_state}
    end
  end

  def update({:remove_all_tokens, tokens_list}, state) do
    new_state =
      Enum.reduce(tokens_list, state, fn {elem, tokens_to_remove}, acc_state ->
        case Map.get(acc_state, elem) do
          nil ->
            acc_state

          {add_tokens, remove_tokens} ->
            new_remove_tokens = MapSet.union(remove_tokens, tokens_to_remove)
            Map.put(acc_state, elem, {add_tokens, new_remove_tokens})
        end
      end)

    {:ok, new_state}
  end

  def update({:reset_tokens, all_tokens}, state) do
    new_state =
      Enum.reduce(all_tokens, state, fn {elem, tokens_to_remove}, acc_state ->
        case Map.get(acc_state, elem) do
          nil ->
            acc_state

          {add_tokens, remove_tokens} ->
            new_remove_tokens = MapSet.union(remove_tokens, tokens_to_remove)
            Map.put(acc_state, elem, {add_tokens, new_remove_tokens})
        end
      end)

    {:ok, new_state}
  end

  def equal(state1, state2) do
    state1 == state2
  end

  # all operations require state downstream
  # Add doesn't need state
  def require_state_downstream({:add, _}) do
    false
  end

  # Add doesn't need state
  def require_state_downstream({:add_all, _}) do
    false
  end

  def require_state_downstream({:remove, _}) do
    true
  end

  def require_state_downstream({:remove_all, _}) do
    true
  end

  def require_state_downstream({:reset, {}}) do
    true
  end

  # Helper function to generate unique tokens
  defp generate_token() do
    # Use node + timestamp + unique ref for uniqueness
    {node(), :erlang.system_time(:nanosecond), make_ref()}
  end
end
