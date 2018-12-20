defmodule Bitcoin.NodeSupervisor do
  use DynamicSupervisor
  @me NodeSupervisor
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: @me)
  end

  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_node(pk, sk, genesis_block, hash_name) do
    {:ok, pid} =
      DynamicSupervisor.start_child(@me, {Bitcoin.Node, {pk, sk, genesis_block, hash_name}})
  end
end
