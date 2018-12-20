defmodule Bitcoin.Miner do
  use GenServer, restart: :transient
  @target "0000" <> "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  # @target "000" <> "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  # @target "00" <> "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

  # API
  def start_link({pk, sk, hash_name}) do
    GenServer.start_link(__MODULE__, {pk, sk},
      name: Bitcoin.Utility.string_to_atom("miner_" <> hash_name)
    )
  end

  # Server
  def init({pk, sk}) do
    {:ok, {pk, sk}}
  end

  # Mining genesis block
  def handle_call({:mine_first, string}, _from, {pk, sk}) do
    signature = Bitcoin.Utility.sign(string, sk)

    updated_unchained_txn = %{
      id: Bitcoin.Utility.getHash(signature),
      signature: signature,
      message: string,
      timestamp: System.system_time()
    }

    {:reply, {mine_first(pk, sk, updated_unchained_txn)}, {pk, sk}}
  end

  def mine_first(pk, sk, first_txn) do
    # Creating the  reward transaction for genesis block
    my_hash = Bitcoin.Utility.getHash(pk)
    reward_msg = %{from: "miner_" <> my_hash, to: "node_" <> my_hash, amount: 1000}
    str_reward_msg = Bitcoin.Utility.txn_msg_to_string(reward_msg)
    signature_of_reward_txn = Bitcoin.Utility.sign(str_reward_msg, sk)

    reward_txn = %{
      id: Bitcoin.Utility.getHash(signature_of_reward_txn),
      signature: signature_of_reward_txn,
      message: reward_msg,
      timestamp: System.system_time()
    }

    # Stringifying transaction set containing first and reward transactions.
    str_txn_set = Bitcoin.Utility.combine([first_txn, reward_txn])

    nonce = Enum.random(1..100)

    new_block_hash = find_first_block_hash(str_txn_set, nonce)

    block = %{
      hash: new_block_hash,
      txns: [first_txn, reward_txn],
      previous_hash: nil,
      timestamp: System.system_time()
    }

    block
  end

  def find_first_block_hash(string, nonce) do
    temp_str = string <> to_string(nonce)
    temp_hash = :crypto.hash(:sha256, temp_str) |> Base.encode16() |> String.downcase()

    if(temp_hash < @target) do
      temp_hash
    else
      find_first_block_hash(string, nonce + 1)
    end
  end

  # Mining logic
  def handle_cast(:mine, {pk, sk}) do
    my_hash = Bitcoin.Utility.getHash(pk)

    # Asking node counterpart for the unchained transactions
    {curr_unchained_txns} =
      GenServer.call(Bitcoin.Utility.string_to_atom("node_" <> my_hash), :get_txns)

    # IO.inspect curr_unchained_txns

    # Taking out only the authenticate transactions
    authenticated_txn_list = authenticate_txns(curr_unchained_txns, my_hash)

    # Sorting autheticated transactions on the basis of timestamp
    sorted_unchained_txns = sort_list(authenticated_txn_list)

    # Block size, i.e. number of transactions in each block
    size_of_txn_set = 5

    if Enum.count(sorted_unchained_txns) < size_of_txn_set do
      # Printing the current blockchain when transaction pool is empty
      {blockchain} =
        GenServer.call(Bitcoin.Utility.string_to_atom("node_" <> my_hash), :get_blockchain)

      IO.inspect(Enum.count(blockchain))
      GenServer.cast(self(), :mine)
      {:noreply, {pk, sk}}
    else
      # Mining using the sorted and authenticated list
      my_hash = Bitcoin.Utility.getHash(pk)
      {txn_set, _} = Enum.split(sorted_unchained_txns, size_of_txn_set)

      # Creating reward transaction
      reward_msg = %{from: "miner_" <> my_hash, to: "node_" <> my_hash, amount: 100}
      str_reward_msg = Bitcoin.Utility.txn_msg_to_string(reward_msg)
      signature_of_reward_txn = Bitcoin.Utility.sign(str_reward_msg, sk)

      reward_txn = %{
        id: Bitcoin.Utility.getHash(signature_of_reward_txn),
        signature: signature_of_reward_txn,
        message: reward_msg,
        timestamp: System.system_time()
      }

      # Adding reward transaction to current transaction set to be used for creating new block
      txn_set = txn_set ++ [reward_txn]

      # Finding the new block's hash
      str_txn_set = Bitcoin.Utility.combine(txn_set)

      [{_, prev_block_hash}] = :ets.lookup(:bitcoin, "prev_block_hash")
      block_string = str_txn_set <> prev_block_hash
      nonce = Enum.random(1..100_000)

      new_block_hash = find_block_hash(block_string, nonce, prev_block_hash)

      if(new_block_hash == :restart) do
        # Restart as some other mined before you
        GenServer.cast(self(), :mine)
        {:noreply, {pk, sk}}
      else
        # Creating new block with new hash
        block = %{
          hash: new_block_hash,
          txns: txn_set,
          previous_hash: prev_block_hash,
          timestamp: System.system_time()
        }

        IO.inspect(new_block_hash)

        # Sending new block to every node
        send_to_all(block, txn_set)

        # Add latest block's hash to ets store
        :ets.insert(:bitcoin, {"prev_block_hash", new_block_hash})

        # Continue mining
        GenServer.cast(self(), :mine)
        {:noreply, {pk, sk}}
      end
    end
  end

  def authenticate_txns(curr_unchained_txns, my_hash) do
    Enum.reduce(curr_unchained_txns, [], fn txn, temp_list ->
      from_pk = GenServer.call(Bitcoin.Utility.string_to_atom(txn.message.from), :get_pk)
      signature = txn.signature

      string = Bitcoin.Utility.txn_msg_to_string(txn.message)

      indexed_blockchain =
        GenServer.call(
          Bitcoin.Utility.string_to_atom("node_" <> my_hash),
          :get_indexed_blockchain
        )

      from_hash = Bitcoin.Utility.string_to_atom(txn.message.from)
      balance_from_hash = Map.get(indexed_blockchain, from_hash)

      if Bitcoin.Utility.verify(string, signature, from_pk) == true &&
           balance_from_hash >= txn.message.amount do
        temp_list ++ [txn]
      else
        temp_list
      end
    end)
  end

  def sort_list(authenticated_txn_list) do
    if authenticated_txn_list != nil do
      Enum.sort_by(authenticated_txn_list, fn txn -> txn.timestamp end)
    else
      []
    end
  end

  def send_to_all(block, txn_set) do
    [{_, all_nodes}] = :ets.lookup(:bitcoin, "nodes")

    Enum.each(all_nodes, fn {hash} ->
      # IO.inspect(hash)
      {:ok} =
        GenServer.call(
          Bitcoin.Utility.string_to_atom("node_" <> hash),
          {:delete_txns, txn_set}
        )

      {:ok} =
        GenServer.call(
          Bitcoin.Utility.string_to_atom("node_" <> hash),
          {:rec_new_block, block}
        )

      {:ok} =
        GenServer.call(
          Bitcoin.Utility.string_to_atom("node_" <> hash),
          :add_latest_block_to_indexded_blockchain
        )

      {:ok} = GenServer.call(Bitcoin.Utility.string_to_atom("node_" <> hash), :update_wallet)
    end)
  end

  def find_block_hash(string, nonce, prev_block_hash) do
    temp_str = string <> to_string(nonce)
    temp_hash = :crypto.hash(:sha256, temp_str) |> Base.encode16() |> String.downcase()

    [{_, temp_prev_block_hash}] = :ets.lookup(:bitcoin, "prev_block_hash")
    # IO.puts nonce

    if(temp_prev_block_hash == prev_block_hash) do
      if(temp_hash < @target) do
        temp_hash
      else
        find_block_hash(string, nonce + 1, prev_block_hash)
      end
    else
      :restart
    end
  end
end
