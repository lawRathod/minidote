defmodule VCGenServer do
  use GenServer

  # The "@impl true" annotations enable checking to ensure the callbacks match the GenServer callbacks.

  # Initialize the GenServer with a given or empty vectorclock
  @impl true
  def init(inital_state = _optional_vectorclock \\ %{}) do
    {:ok, inital_state}
  end

  @impl true
  def handle_call(:new, _from, state) do
    {:reply, _return_value = Vectorclock.new(), state}
  end

  @impl true
  def handle_call(:increment, from, state) do
    new_state = Vectorclock.increment(state, from)
    {:reply, new_state, new_state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, _return_value = state, state}
  end

  @impl true
  def handle_call({:get, pid}, _from, state) do
    {:reply, _return_value = Vectorclock.get(state, pid), state}
  end

  @impl true
  def handle_call({:leq, other_vc}, _from, state) do
    {:reply, _return_value = Vectorclock.leq(other_vc, state), state}
  end

  # Catch all for calls
  @impl true
  def handle_call(request, from, state ) do
    IO.inspect({"Unexpected call: ", request, " From: ", from, " State: ", state})
    {:reply, :unexpected, state}
  end



  @impl true
  def handle_cast({:merge, other_vc}, state) do
    {:noreply, _new_state = Vectorclock.merge(other_vc, state)}
  end

  # Catch all for casts
  @impl true
  def handle_cast(request, state ) do
    IO.inspect({"Unexpected cast: ", request, " State: ", state})
    {:noreply, state}
  end

end

