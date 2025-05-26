defmodule Chat.Server do
  use GenServer

  # Feel free to modify the functions in any shape and form as needed

  @impl true
    def init(:ok) do
    # Setup server state
    {:ok, state = {}}
  end

  @impl true
  def handle_call({:join, _some_more_args}, from, state) do
    {:reply, return = :ok, state}
  end

  @impl true
  def handle_call({:leave, _some_more_args}, from, state) do
    {:reply, return = :ok, state}
  end

  @impl true
  def handle_call({:message, _some_more_args}, from, state) do
    {:reply, return = :ok, state}
  end

  # Optional function for testing
  @impl true
  def handle_call({:status}, from, state) do
    {:reply, return = :ok, state}
  end

  @impl true
  def handle_call(request, from, state ) do
    IO.inspect({"Unexpected call: ", request, " From: ", from, " State: ", state})
    {:reply, :unexpected, state}
  end

  @impl true
  def handle_cast(request, state ) do
    IO.inspect({"Unexpected cast: ", request, " State: ", state})
    {:noreply, state}
  end

end
