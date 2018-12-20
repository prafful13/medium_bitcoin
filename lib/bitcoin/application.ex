defmodule Bitcoin.Application do
  use Application

  def start(_type, _args) do
    children = [
      Bitcoin.NodeSupervisor,
      Bitcoin.MinerSupervisor,
      Bitcoin.Driver
    ]

    opts = [strategy: :one_for_one, name: Bitcoin.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
