defmodule Repseat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    IO.puts("Starting repseat app")
    {:ok, _} = :application.ensure_all_started(:ra)

    children = [
      # Starts a worker by calling: Repseat.Worker.start_link(arg)
      {Repseat.Raft, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [intensity: 0, persiod: 1, strategy: :one_for_all, name: Repseat.Supervisor]
    {:ok, _} = Supervisor.start_link(children, opts)
  end
end
