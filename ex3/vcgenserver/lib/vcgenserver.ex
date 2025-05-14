defmodule VCGenServer do
  use GenServer


  # Some example callback to init the GenServer
  # ToDo: rewrite
  @impl true
  def init(element) do
    initial_state = String.split(elements, ",", trim: true)
    {:ok, initial_state}
  end


  # Some example callback to receive a message and return a value as to_caller the GenServer
  # ToDo: rewrite
  @impl true
  def handle_call(:pop, from, state) do
    [to_caller | new_state] = state
    {:reply, to_caller, new_state}
  end

  # Some other example callback to receive a message and return a value as to_caller the GenServer
  # ToDo: rewrite
  @impl true
  def handle_call(:sayHi, from, state) do
    IO.puts("Hi :)")
    to_caller = "Hi :)"
    {:reply, to_caller, state}
  end

  # Some example callback to receive a message to the GenServer
  # ToDo: rewrite
  @impl true
  def handle_cast({:push, element}, state) do
    new_state = [element | state]
    {:noreply, new_state}
  end

  # ToDo: Add more handle_cast and handle_call callbacks as needed
end

