defmodule Chat.Server do
  use GenServer

  @impl true
    def init(server_group) do
    # Setup server state
    local_client_group = Node.self()
    {:ok, pg_pid} = :pg.start_link()
    :pg.join(:default, self())
    {:ok , _state = {server_group, local_client_group, pg_pid}}
  end

  # ---- Join a chat group ------------------------------------------------------------------------
  @impl true
  def handle_cast({:join, receiving_pid}, state = {server_group, lcg, _pg_pid}) do
    :pg.join(lcg, receiving_pid)
    broadcast(inspect(Node.self()), "#{inspect(receiving_pid)} joined.", :pg.get_members(server_group))
    {:noreply, state}
  end

  # ---- Leave a chat group -----------------------------------------------------------------------
  @impl true
  def handle_cast({:leave, receiving_pid}, state = {server_group, lcg, _pg_pid}) do
    broadcast(inspect(Node.self()), "#{inspect(receiving_pid)} left.", :pg.get_members(server_group))
    :pg.leave(lcg, receiving_pid)
    {:noreply, state}
  end

  # ---- Send a message if in group ---------------------------------------------------------------
  @impl true
  def handle_cast({:message, source, m}, state = {server_group, _lcg, _pg_pid}) do
    broadcast(source, m, :pg.get_members(server_group))
    {:noreply, state}
  end

  # ---- Forward messages to clients via best effort broadcast ------------------------------------
  @impl true
  def handle_cast({:forward, source, message}, state = {_server_group, lcg, _pg_pid}) do
    Enum.each(:pg.get_members(lcg), fn client_pid -> send(client_pid, {:receive, source, message}) end)
    {:noreply, state}
  end

  # ---- Catch all for cast -----------------------------------------------------------------------
  @impl true
  def handle_cast(request, state ) do
    IO.inspect({"Unexpected cast: ", request, " State: ", state})
    {:noreply, state}
  end

  # ---- Get server status ------------------------------------------------------------------------
  @impl true
  def handle_call({:status}, from, state = {server_group, lcg, pg_pid}) do
    {:reply, {
      " Status Requestor: ", from,
      " Server Group: ", server_group,
      " Local Client Group: ", lcg,
      " Server PID: ", self(),
      " Process Group PID: ", pg_pid,
      " Server Node: ", Node.self(),
      " Server State: ", state,
      " Reachable Servers: ", :pg.get_members(server_group),
      " Locally reachable Clients: ", :pg.get_members(lcg),
      " Server Process Info: ", Process.info(self())
      }, state
    }
  end

  # ---- Catch all for call -----------------------------------------------------------------------
  @impl true
  def handle_call(request, from, state) do
    IO.inspect({"Unexpected call: ", request, " From: ", from, " State: ", state})
    {:reply, :unexpected_request, state}
  end

  # ---- Shutting down the server -----------------------------------------------------------------
  @impl true
  def terminate(reason, _state = {server_group, _lcg, _pg_pid}) do
    broadcast(inspect(Node.self()), "Node Server is shutting down because of #{inspect(reason)}", :pg.get_members(server_group))
  end

  # ---- Best effort broadcast to other servers ---------------------------------------------------
  def broadcast(source, message, server_list) do
    Enum.each(server_list, fn (server_pid) -> GenServer.cast(server_pid, {:forward, source, message}) end)
  end

end
