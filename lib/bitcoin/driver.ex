defmodule Bitcoin.Driver do
  use GenServer
  @me __MODULE__

  # API
  def start_link(_) do
    GenServer.start_link(__MODULE__, :no_args, name: @me)
  end

  # SERVER
  def init(:no_args) do
    Process.send_after(self(), :kickoff, 0)
    {:ok, {}}
  end

  def handle_info(:kickoff, {}) do
    numNodes = 20
    numMiners = 5
    :ets.new(:bitcoin, [:set, :public, :named_table])

    {numNodes, numMiners}
    |> spawn_miners()
    |> create_genesis_block()
    |> spawn_miner_nodes()
    |> spawn_nodes()
    |> start_mining()
    |> make_transactions()

    {:noreply, {}}
  end

  def spawn_miners({numNodes, numMiners}) do
    miner_pk_hash_sk =
      Enum.map(1..numMiners, fn _ ->
        {:ok, {sk, pk}} = RsaEx.generate_keypair()
        hash_name = Bitcoin.Utility.getHash(pk)
        {:ok, _} = Bitcoin.MinerSupervisor.add_miner(pk, sk, hash_name)
        {pk, hash_name, sk}
      end)

    miners =
      Enum.map(miner_pk_hash_sk, fn {_, hash_name, _} ->
        {hash_name}
      end)

    :ets.insert(:bitcoin, {"miners", miners})
    {miner_pk_hash_sk, numNodes}
  end

  def create_genesis_block({miner_pk_hash_sk, numNodes}) do
    [{_, first_miner_hash, _} | _] = miner_pk_hash_sk

    {genesis_block} =
      GenServer.call(
        Bitcoin.Utility.string_to_atom("miner_" <> first_miner_hash),
        {:mine_first, "The quick brown fox jumps over the lazy dog"}
      )

    :ets.insert(:bitcoin, {"prev_block_hash", genesis_block.hash})
    IO.inspect(genesis_block)
    {genesis_block, miner_pk_hash_sk, numNodes}
  end

  def spawn_miner_nodes({genesis_block, miner_pk_hash_sk, numNodes}) do
    miner_node_hash =
      Enum.map(miner_pk_hash_sk, fn {pk, hash_name, sk} ->
        {:ok, _} = Bitcoin.NodeSupervisor.add_node(pk, sk, genesis_block, hash_name)

        {:ok} =
          GenServer.call(Bitcoin.Utility.string_to_atom("node_" <> hash_name), :update_wallet)

        {:ok} =
          GenServer.call(
            Bitcoin.Utility.string_to_atom("node_" <> hash_name),
            :add_latest_block_to_indexded_blockchain
          )

        {hash_name}
      end)

    {genesis_block, miner_node_hash, miner_pk_hash_sk, numNodes}
  end

  def spawn_nodes({genesis_block, miner_node_hash, miner_pk_hash_sk, numNodes}) do
    [{_, first_miner_hash, _} | _] = miner_pk_hash_sk

    node_hash =
      Enum.map(1..numNodes, fn _ ->
        {:ok, {sk, pk}} = RsaEx.generate_keypair()
        hash_name = Bitcoin.Utility.getHash(pk)

        {:ok, _} = Bitcoin.NodeSupervisor.add_node(pk, sk, genesis_block, hash_name)

        {:ok} =
          GenServer.call(
            Bitcoin.Utility.string_to_atom("node_" <> hash_name),
            :add_latest_block_to_indexded_blockchain
          )

        {hash_name}
      end)

    # Adding all nodes to our ets store
    all_nodes = miner_node_hash ++ node_hash
    :ets.insert(:bitcoin, {"nodes", all_nodes})

    # Every spawned node requests bitcoins from the miner which created the genesis block
    Enum.each(all_nodes, fn {hash} ->
      if hash != first_miner_hash do
        GenServer.cast(
          Bitcoin.Utility.string_to_atom("node_" <> first_miner_hash),
          {:req_for_bitcoin, 10, hash}
        )
      end
    end)

    {miner_pk_hash_sk}
  end

  def start_mining({miner_pk_hash_sk}) do
    acc =
      Enum.reduce(miner_pk_hash_sk, 0, fn {_, miner_hash, _}, acc ->
        GenServer.cast(Bitcoin.Utility.string_to_atom("miner_" <> miner_hash), :mine)
        acc + 1
      end)

    {acc, miner_pk_hash_sk}
  end

  def make_transactions({acc, miner_pk_hash_sk}) do
    [{_, all_nodes}] = :ets.lookup(:bitcoin, "nodes")
    [{_, first_miner_hash, _} | _] = miner_pk_hash_sk

    if(acc == 5) do
      Enum.each(1..(acc * 2000), fn i ->
        {node1_hash} = Enum.random(all_nodes)
        {node2_hash} = Enum.random(all_nodes)
        amount = Enum.random(1..10)

        GenServer.cast(
          Bitcoin.Utility.string_to_atom("node_" <> node1_hash),
          {:req_for_bitcoin, amount, node2_hash}
        )
      end)
    end
  end
end
