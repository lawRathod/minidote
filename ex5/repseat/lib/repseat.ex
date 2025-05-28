defmodule Repseat.Raft do

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end


  def start_link(_) do
    {:ok, spawn_link(fn() ->
      ## All servers in a Ra cluster are named processes on BeamVM nodes.
      ## The nodes must have distribution enabled and be able to
      ## communicate with each other.

      ## These nodes will host Ra nodes.
      ## They are assumed to be running or
      ## come online shortly after Ra cluster formation is started

      ## the environment variable R_NODES supplies the configuration
      ## e.g.
      ## R_NODES='ra1@hostname.local,ra2@hostname.local'
      tmp = String.split(System.get_env("R_NODES", ""), ",")
      all_nodes = for n <- tmp, n != "" do
        node_atom = String.to_atom(n)
        IO.puts("Connecting to " <> n)

        ## This will check for distribution connectivity.
        ## If nodes cannot communicate with each other,
        ## Ra nodes would not be able to cluster or communicate either.
        :ok = connect_retry(node_atom)

        node_atom
      end

      # state machine that implements logic and initial state
      #machine = {:simple, &:erlang.'+'/2, 0}
      machine = {:module, :'Elixir.Repseat.Raft.Machine', %{}}

      node_ids = for n <- all_nodes do {:node, n} end

      ## The Ra application has to be started
      for n <- all_nodes do :rpc.call(n, :ra, :start, []) end
      {:ok, _started, _notstarted} = :ra.start_cluster(:default, :my_cluster, machine, node_ids)

      :ok
    end)}
  end


  def connect_retry(node) do
    case Node.ping(node) do
      :pong ->
        :ok
      :pang ->
        Process.sleep(1000) # 1 sec delay
        connect_retry(node)
    end
  end
end
