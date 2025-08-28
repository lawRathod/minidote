defmodule LinkLayerDistr do
  @moduledoc """
  Implementation of distributed LinkLayer using Erlang process groups.

  This module provides the actual distributed functionality for LinkLayer,
  using Erlang's `:pg` (process groups) for node discovery and coordination.
  It handles node connections, message routing, and cluster membership.

  ## Key Features

  - **Process Group Membership**: Uses `:pg` for automatic node discovery
  - **Automatic Connections**: Discovers and connects to nodes via environment variables
  - **Message Routing**: Routes messages between cluster members
  - **Fault Tolerance**: Handles node failures and network issues

  ## Node Discovery

  Nodes are discovered through:
  1. `MINIDOTE_NODES` environment variable containing comma-separated node names
  2. Process group membership - nodes join the same group to find each other
  3. Automatic connection attempts with exponential backoff

  ## Internal State

  - `:group_name` - Process group name for cluster membership  
  - `:respond_to` - Registered receiver for incoming messages
  """

  use GenServer
  require Logger

  @doc """
  Starts the LinkLayerDistr GenServer for the specified group.

  ## Parameters

  - `group_name`: Atom identifying the process group

  ## Returns

  - `{:ok, pid}` on success
  - `{:error, reason}` on failure
  """
  @spec start_link(atom()) :: GenServer.on_start()
  def start_link(group_name) do
    GenServer.start_link(__MODULE__, group_name)
  end

  @impl true
  @spec init(atom()) :: {:ok, map()}
  def init(group_name) do
    # initially, try to connect with other erlang nodes
    spawn_link(&find_other_nodes/0)
    :pg.start_link()
    :pg.join(group_name, self())
    {:ok, %{:group_name => group_name, :respond_to => :none}}
  end

  @impl true
  @spec handle_call({:send, term(), pid()}, GenServer.from(), map()) :: {:reply, :ok, map()}
  def handle_call({:send, data, node}, _from, state) do
    GenServer.cast(node, {:remote, data})
    {:reply, :ok, state}
  end

  @impl true
  @spec handle_call({:register, pid()}, GenServer.from(), map()) :: {:reply, :ok, map()}
  def handle_call({:register, r}, _from, state) do
    {:reply, :ok, %{state | :respond_to => r}}
  end

  @impl true
  @spec handle_call(:all_nodes, GenServer.from(), map()) :: {:reply, {:ok, [pid()]}, map()}
  def handle_call(:all_nodes, _from, state) do
    members = :pg.get_members(state[:group_name])
    {:reply, {:ok, members}, state}
  end

  @impl true
  @spec handle_call(:other_nodes, GenServer.from(), map()) :: {:reply, {:ok, [pid()]}, map()}
  def handle_call(:other_nodes, _from, state) do
    members = :pg.get_members(state[:group_name])
    other_members = for n <- members, n !== self(), do: n
    {:reply, {:ok, other_members}, state}
  end

  @impl true
  def handle_call(:this_node, _from, state) do
    {:reply, {:ok, self()}, state}
  end

  @impl true
  def handle_cast({:remote, msg}, state) do
    send(state[:respond_to], msg)
    {:noreply, state}
  end

  def find_other_nodes() do
    nodes = os_or_app_env()
    Logger.notice("Connecting #{node()} to other nodes: #{inspect(nodes)}")
    try_connect(nodes, 500)
  end

  defp try_connect(nodes, t) do
    {ping, pong} = :lists.partition(fn n -> :pong == :net_adm.ping(n) end, nodes)

    for n <- ping do
      Logger.notice("Connected to node #{n}")
    end

    case t > 1000 do
      true ->
        for n <- pong do
          Logger.notice("Failed to connect #{node()} to node #{n}")
        end

      _ ->
        :ok
    end

    case pong do
      [] ->
        Logger.notice("Connected to all nodes")

      _ ->
        :timer.sleep(t)
        try_connect(pong, min(2 * t, 60000))
    end
  end

  def os_or_app_env() do
    nodes = :string.tokens(:os.getenv(~c"MINIDOTE_NODES", ~c""), ~c",")

    case nodes do
      ~c"" ->
        :application.get_env(:microdote, :microdote_nodes, [])

      _ ->
        for n <- nodes do
          :erlang.list_to_atom(n)
        end
    end
  end
end
