defmodule VectorClock do
  @moduledoc """
  Vector clock implementation for tracking causal relationships between events
  in a distributed system.

  A vector clock is a map where keys are node identifiers and values are logical timestamps.
  Vector clocks enable ordering of events in distributed systems without requiring
  global coordination or synchronized clocks.

  ## Causal Ordering

  Vector clocks establish a happens-before relationship between events:
  - If event A's vector clock is dominated by event B's vector clock, then A happened before B
  - If neither dominates the other, the events are concurrent
  - If all entries are equal, the events represent the same causal state

  ## Operations

  - **Increment**: Advance the local node's timestamp when an event occurs
  - **Merge**: Combine two vector clocks by taking the maximum of each node's timestamp
  - **Compare**: Determine the causal relationship between two vector clocks

  ## Examples

      # Create vector clocks for two nodes
      clock1 = VectorClock.new(:node1)    # %{node1: 0}
      clock2 = VectorClock.new(:node2)    # %{node2: 0}
      
      # Node1 performs an operation
      clock1 = VectorClock.increment(clock1, :node1)  # %{node1: 1}
      
      # Node2 receives the update and merges
      clock2 = VectorClock.merge(clock2, clock1)      # %{node1: 1, node2: 0}
      
      # Check causal ordering
      VectorClock.compare(clock1, clock2)  # :before (clock1 happened before clock2)
  """

  @type t :: %{node() => non_neg_integer()}

  @doc """
  Creates a new empty vector clock.
  """
  @spec new() :: t()
  def new(), do: %{}

  @doc """
  Creates a new vector clock with the current node initialized to 0.
  """
  @spec new(node()) :: t()
  def new(node), do: %{node => 0}

  @doc """
  Increments the clock for the given node.
  """
  @spec increment(t(), node()) :: t()
  def increment(clock, node) do
    Map.update(clock, node, 1, &(&1 + 1))
  end

  @doc """
  Merges two vector clocks by taking the maximum value for each node.
  This represents the "happens-before" relationship.
  """
  @spec merge(t(), t()) :: t()
  def merge(clock1, clock2) do
    all_nodes = (Map.keys(clock1) ++ Map.keys(clock2)) |> Enum.uniq()

    Enum.reduce(all_nodes, %{}, fn node, acc ->
      val1 = Map.get(clock1, node, 0)
      val2 = Map.get(clock2, node, 0)
      Map.put(acc, node, max(val1, val2))
    end)
  end

  @doc """
  Compares two vector clocks for causal ordering.

  Returns:
  - :before if clock1 happens before clock2
  - :after if clock1 happens after clock2  
  - :concurrent if they are concurrent (no causal relationship)
  - :equal if they are identical
  """
  @spec compare(t(), t()) :: :before | :after | :concurrent | :equal
  def compare(clock1, clock2) do
    all_nodes = (Map.keys(clock1) ++ Map.keys(clock2)) |> Enum.uniq()

    {before_count, after_count, equal_count} =
      Enum.reduce(all_nodes, {0, 0, 0}, fn node, {before_acc, after_acc, equal_acc} ->
        val1 = Map.get(clock1, node, 0)
        val2 = Map.get(clock2, node, 0)

        cond do
          val1 < val2 -> {before_acc + 1, after_acc, equal_acc}
          val1 > val2 -> {before_acc, after_acc + 1, equal_acc}
          true -> {before_acc, after_acc, equal_acc + 1}
        end
      end)

    total_nodes = length(all_nodes)

    cond do
      equal_count == total_nodes -> :equal
      before_count > 0 and after_count == 0 -> :before
      after_count > 0 and before_count == 0 -> :after
      true -> :concurrent
    end
  end

  @doc """
  Checks if clock1 is causally before clock2.
  This means all entries in clock1 are <= corresponding entries in clock2,
  and at least one is strictly less.
  """
  @spec before?(t(), t()) :: boolean()
  def before?(clock1, clock2) do
    compare(clock1, clock2) == :before
  end

  @doc """
  Checks if clock1 is causally after clock2.
  """
  @spec after?(t(), t()) :: boolean()
  def after?(clock1, clock2) do
    compare(clock1, clock2) == :after
  end

  @doc """
  Checks if two clocks are concurrent (neither happens before the other).
  """
  @spec concurrent?(t(), t()) :: boolean()
  def concurrent?(clock1, clock2) do
    compare(clock1, clock2) == :concurrent
  end

  @doc """
  Gets the timestamp for a specific node, defaulting to 0 if not present.
  """
  @spec get(t(), node()) :: non_neg_integer()
  def get(clock, node) do
    Map.get(clock, node, 0)
  end

  @doc """
  Sets the timestamp for a specific node.
  """
  @spec put(t(), node(), non_neg_integer()) :: t()
  def put(clock, node, value) do
    Map.put(clock, node, value)
  end

  @doc """
  Returns all nodes present in the vector clock.
  """
  @spec nodes(t()) :: [node()]
  def nodes(clock) do
    Map.keys(clock)
  end

  @doc """
  Converts vector clock to a readable string format.
  """
  @spec to_string(t()) :: String.t()
  def to_string(clock) do
    clock
    |> Enum.sort()
    |> Enum.map(fn {node, time} -> "#{node}:#{time}" end)
    |> Enum.join(", ")
    |> then(fn s -> "{#{s}}" end)
  end
end
