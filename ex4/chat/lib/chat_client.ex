defmodule Chat.Client do

  # Feel free to modify the functions in any shape and form as needed

  def setup(_addition_arguments) do
    # Connect to server
    # Send "Joined Chat" message
  end

  def start_link(_addition_arguments) do
    GenServer.start_link(Chat.Server, :ok, [name: :local_chat_server])
  end

  def join(_addition_arguments) do
    GenServer.cast(Process.whereis(:local_chat_server), {:join, self()})
  end

  def leave(_addition_arguments) do
    GenServer.cast(Process.whereis(:local_chat_server), {:leave, self()})
  end

  def message(msg, _addition_arguments) do
    GenServer.cast(Process.whereis(:local_chat_server), {:message, self(), msg})
  end

  # Optional
  def terminate_local_server (_addition_arguments) do
    :ok = GenServer.stop(Process.whereis(:local_chat_server), :normal, 10)
  end

  def status () do
    IO.inspect(Node.alive?())
    IO.inspect(Node.list())
    IO.inspect(Node.self())
    IO.inspect(self())
    IO.inspect(Process.whereis(:local_chat_server))

    # Additional Process info. Includes mailbox size and more
    # IO.inspect(Process.info(self()))
    # IO.inspect(Process.info(Process.whereis(:local_chat_server))
  end
end
