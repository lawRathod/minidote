defmodule Chat.Client do

  def start() do
    receiver_pid = spawn_link(&receiver/0)

    start_link()
    join(receiver_pid)
    print_help()
    chat_loop(receiver_pid)
    leave(receiver_pid)
  end

  def receiver() do
      receive do
        {:receive, source, message} -> IO.puts("#{inspect(source)}:  #{message}")
        anything -> IO.inspect(anything)
      end
      receiver()
  end

  def chat_loop(receiver_pid) do
    input = String.trim(IO.gets("> "))
    case input do
      "help" -> print_help(); chat_loop(receiver_pid)
      "connect" -> connect_to_server(Node.alive?()); chat_loop(receiver_pid)
      "status" -> status(receiver_pid); chat_loop(receiver_pid)
      "STATUS" -> status_all(receiver_pid); chat_loop(receiver_pid)
      "exit" -> leave(receiver_pid); IO.puts("Chat closed")
      "shutdown" -> leave(receiver_pid); terminate_server(); IO.puts("Chat closed and Server terminated")
      "clear" -> IEx.Helpers.clear(); chat_loop(receiver_pid)
      _ -> message(input); chat_loop(receiver_pid)
    end
  end

  def connect_to_server(true) do
    node_name = IO.gets("  Please enter the name of the node you want to connect to.\n  Write it like the following example  node_name@localhost\n  Connect #{Node.self()}   to  ")
    IO.puts("Did it work? #{inspect(Node.connect(String.to_atom(String.trim(node_name))))}")
    IO.puts("The list of connected nodes is:\n #{inspect(Node.list())}")
    Enum.each(Node.list(), fn node -> Node.ping(node) end)
  end

  def connect_to_server(false) do
    IO.puts("Your node has not been correctly started! Restart it with \niex --sname node_name@localhost --cookie secret -S mix")
    IO.puts("Exit the current shell with 2x CRTL+C or CRTL+g followed by q and ENTER")
  end

  def start_link() do
    GenServer.start_link(Chat.Server, :default, [name: :local_chat_server])
  end

  def join(receiver_pid) do
    GenServer.cast(Process.whereis(:local_chat_server), {:join, receiver_pid})
  end

  def leave(receiver_pid) do
    GenServer.cast(Process.whereis(:local_chat_server), {:leave, receiver_pid})
  end

  def message(msg) do
    GenServer.cast(Process.whereis(:local_chat_server), {:message, self(), msg})
  end

  def terminate_server() do
    GenServer.stop(Process.whereis(:local_chat_server), :normal, 100)
  end

  def status(receiver_pid \\ nil) do
    IO.puts("Client Process PID:")
    IO.inspect(self())
    IO.puts("")

    IO.puts("Receiver Process PID:")
    IO.inspect(receiver_pid)
    IO.puts("")

    IO.puts("Local Node information:")
    Node.alive?()
    && IO.inspect(Node.self())
    && IO.inspect(Node.list())
    || IO.puts("Node is offline")
    IO.puts("")

    IO.puts("Server Process PID:")
    is_pid(Process.whereis(:local_chat_server))
    && IO.inspect(Process.whereis(:local_chat_server))
    && IO.puts("")
    && IO.puts("Server info:")
    && IO.inspect(GenServer.call(Process.whereis(:local_chat_server), {:status}))
    || IO.puts("Not yet linked")
    IO.puts("")
  end

  def status_all(receiver_pid \\ nil) do
    status(receiver_pid)
    IO.puts("Client-Main:")
    IO.inspect(Process.info(self()))
    IO.puts("")

    IO.puts("Client-Receiver:")
    IO.inspect(receiver_pid)
    Process.alive?(receiver_pid)
    && IO.inspect(Process.info(receiver_pid))
    || IO.puts("Receiver unavailable")
    IO.puts("")

    Process.alive?(Process.whereis(:local_chat_server))
    && IO.puts("Server:")
    && IO.inspect(Process.info(Process.whereis(:local_chat_server)))
    || IO.puts("")
  end

  def print_help() do
    IO.puts("You can type any message and send it through pressing enter. Some messages have special behaviour:\n exit -> leave the chat\n connect -> Connect to another node\n status -> prints the current status of the system\n STATUS -> prints more information\n clear -> clears the console\n shutdown -> leaves the chat and terminates the node's chat server\n help -> prints this text")
  end

end
