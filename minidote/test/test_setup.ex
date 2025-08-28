defmodule TestSetup do
  require Logger
  require Consts

  def init() do
    Logger.notice("Deleting old data directory")
    # Delete old data directory if it exists
    data_dir = Consts.data_dir()

    if File.exists?(data_dir) do
      File.rm_rf!(data_dir)
      Logger.notice("Deleted old data directory: #{data_dir}")
    else
      Logger.notice("No old data directory to delete")
    end

    Logger.notice("Starting distributed setup")
    # Check if already distributed
    case Node.self() do
      :nonode@nohost ->
        Logger.notice("Starting net_kernel...")

        case :net_kernel.start([:"master@127.0.0.1"]) do
          {:ok, _pid} ->
            Logger.notice("Net kernel started successfully")

          {:error, {:already_started, _pid}} ->
            Logger.notice("Net kernel already started")

          {:error, reason} ->
            Logger.error("Failed to start net_kernel: #{inspect(reason)}")
            {:error, reason}
        end

      node_name ->
        Logger.notice("Already distributed as: #{node_name}")
    end

    # Start boot server
    case :erl_boot_server.start([{127, 0, 0, 1}]) do
      {:ok, _pid} ->
        Logger.notice("Boot server started")

      {:error, {:already_started, _pid}} ->
        Logger.notice("Boot server already started")

      {:error, reason} ->
        Logger.error("Failed to start boot server: #{inspect(reason)}")
    end

    Logger.notice("Current node: #{Node.self()}")
    Logger.notice("Finished distributed setup")
    :ok
  end

  # assumes that the node is down!
  def start_node(name) do
    Logger.notice("Booting distributed node #{name}")
    cookie = :erlang.get_cookie()
    Logger.notice("Using cookie: #{cookie}")

    {:ok, _peer, node} =
      :peer.start_link(%{
        name: :"#{name}",
        host: ~c"127.0.0.1",
        args: [
          ~c"-setcookie",
          ~c"#{cookie}",
          ~c"-loader",
          ~c"inet",
          ~c"-hosts",
          ~c"127.0.0.1"
        ]
      })

    Logger.notice("Started node #{node}")

    # initialize environment
    rpc = &(_ = :rpc.call(node, &1, &2, &3))
    rpc.(:code, :add_paths, [:code.get_path()])
    rpc.(Application, :ensure_all_started, [:mix])
    rpc.(Application, :ensure_all_started, [:logger])
    rpc.(Logger, :configure, [[level: Logger.level()]])
    rpc.(Mix, :env, [Mix.env()])
    Logger.notice("Starting minidote on node: #{inspect(node)}")
    rpc.(Application, :ensure_all_started, [:minidote])

    connected = Node.list()
    IO.puts("Connected nodes: #{inspect(connected)}")

    node
  end

  @spec stop_node(atom) :: :ok
  def stop_node(node) do
    # Use slave.stop for now until peer module is fully adopted
    # The warning can be ignored as this is test code
    :slave.stop(node)
  end

  @spec stop_nodes([atom]) :: :ok
  def stop_nodes(nodes) do
    # Use slave.stop for now until peer module is fully adopted
    # The warning can be ignored as this is test code
    Enum.each(nodes, &:slave.stop/1)
  end

  @doc """
  Start nodes with LinkLayer auto-discovery instead of manual Node.connect.
  Nodes will automatically discover each other via the LinkLayer process group.
  """
  def start_nodes_with_linklayer(node_names, _group_name \\ :minidote_cluster) do
    # Set environment variable for LinkLayer node discovery
    all_node_names = Enum.map(node_names, &:"#{&1}@127.0.0.1")
    node_list_string = all_node_names |> Enum.map(&Atom.to_string/1) |> Enum.join(",")

    # Start all nodes with the environment variable set
    nodes =
      Enum.map(node_names, fn name ->
        node = start_node(name)

        # Set environment variable on the remote node for LinkLayer discovery
        :rpc.call(node, System, :put_env, ["MINIDOTE_NODES", node_list_string])

        # Start Minidote on the node (which will start BroadcastLayer and LinkLayer)
        :rpc.call(node, Minidote, :start_link, [Minidote.Server])

        node
      end)

    # Wait for LinkLayer discovery to complete
    Process.sleep(500)

    Logger.notice(
      "Started #{length(nodes)} nodes with LinkLayer auto-discovery: #{inspect(nodes)}"
    )

    nodes
  end

  @doc """
  Wait for nodes to discover each other via LinkLayer.
  """
  def wait_for_linklayer_discovery(nodes, timeout \\ 2000) do
    start_time = :erlang.monotonic_time(:millisecond)

    wait_for_discovery_loop(nodes, start_time, timeout)
  end

  defp wait_for_discovery_loop(nodes, start_time, timeout) do
    current_time = :erlang.monotonic_time(:millisecond)

    if current_time - start_time > timeout do
      {:error, :timeout}
    else
      # Check if all nodes can see each other via BroadcastLayer
      all_connected =
        Enum.all?(nodes, fn node ->
          case :rpc.call(node, BroadcastLayer, :get_nodes, []) do
            {:ok, other_nodes} -> length(other_nodes) >= length(nodes) - 1
            _ -> false
          end
        end)

      if all_connected do
        :ok
      else
        Process.sleep(100)
        wait_for_discovery_loop(nodes, start_time, timeout)
      end
    end
  end

  def mock_link_layer(nodes, options) do
    # Ensure current module is loaded on all nodes
    for node <- nodes do
      :rpc.call(node, Code, :ensure_loaded, [__MODULE__])
    end

    IO.puts("Mocking link layer for  #{inspect(nodes)}")

    for node <- nodes do
      :rpc.cast(node, __MODULE__, :add_delay_r, [self(), node(), options])
    end

    IO.puts("Waiting delay for #{inspect(nodes)}")

    for node <- nodes do
      receive do
        {:add_delay_r_done, ^node} -> :ok
      end
    end

    IO.puts("Added delay of #{Map.get(options, :delay)}ms for #{inspect(nodes)}")
    :ok
  end

  def add_delay_r(requester, this_node, options) do
    :application.ensure_all_started(:meck)
    :ok = :meck.new(:"Elixir.LinkLayer", [:passthrough])

    :ok =
      :meck.expect(:"Elixir.LinkLayer", :send, fn ll, data, receiver ->
        spawn(fn ->
          case :maps.find(:delay, options) do
            {:ok, ms} when is_number(ms) ->
              :timer.sleep(ms)

            {:ok, f} when is_function(f) ->
              ms = f.(node(), receiver)
              :timer.sleep(ms)

            :error ->
              :ok
          end

          case :maps.get(:debug, options, false) do
            true ->
              # :ok #TODO use this_node
              :rpc.call(this_node, :ct, :pal, [
                "Sending message from ~p to ~p:~n ~180p",
                [node(), Receiver, Data]
              ])

            false ->
              :ok
          end

          apply(:meck_util.original_name(:"Elixir.LinkLayer"), :send, [ll, data, receiver])
        end)
      end)

    # answer to requester
    send(requester, {:add_delay_r_done, node()})
    # wait until monitor is done:
    monitor_ref = :erlang.monitor(:process, requester)

    receive do
      {:DOWN, ^monitor_ref, _type, _object, _info} ->
        :ok
    end
  end
end
