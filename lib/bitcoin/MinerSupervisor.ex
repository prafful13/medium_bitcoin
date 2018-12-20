defmodule Bitcoin.MinerSupervisor do
  use DynamicSupervisor
  @me MinerSupervisor
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: @me)
  end

  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_miner(pk, sk, hash_name) do
    {:ok, pid} = DynamicSupervisor.start_child(@me, {Bitcoin.Miner, {pk, sk, hash_name}})
  end
end
