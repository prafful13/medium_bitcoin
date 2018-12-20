defmodule Bitcoin.Node do
  use GenServer, restart: :transient

  # API
  def start_link({pk, sk, genesis_block, hash_name}) do
    GenServer.start_link(__MODULE__, {pk, sk, genesis_block},
      name: Bitcoin.Utility.string_to_atom("node_" <> hash_name)
    )
  end

  # Server
  def init({pk, sk, genesis_block}) do
    {:ok, {pk, sk, [genesis_block], [], 0, %{}}}
  end

  def handle_call(:get_pk, _from, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}) do
    {:reply, pk, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}}
  end

  def handle_call(
        :get_indexed_blockchain,
        _from,
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    {:reply, indexed_blockchain, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}}
  end

  def handle_call(
        {:delete_txns, txn},
        _from,
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    updated_txns = txn_list -- txn
    {:reply, {:ok}, {pk, sk, blockchain, updated_txns, balance, indexed_blockchain}}
  end

  def handle_call(
        {:rec_new_block, new_block},
        _from,
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    updated_blockchain = blockchain ++ [new_block]

    txn_list = txn_list -- new_block.txns
    {:reply, {:ok}, {pk, sk, updated_blockchain, txn_list, balance, indexed_blockchain}}
  end

  def handle_call(
        :update_wallet,
        _from,
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    my_name = "node_" <> Bitcoin.Utility.getHash(pk)

    latest_block = Enum.at(blockchain, -1)
    txns = latest_block.txns

    updated_balance =
      Enum.reduce(txns, balance, fn txn, acc ->
        if(Kernel.is_map(txn.message) == true) do
          cond do
            txn.message.from == my_name ->
              acc

            txn.message.to == my_name ->
              acc + txn.message.amount

            txn.message.from != my_name && txn.message.to != my_name ->
              acc
          end
        else
          acc
        end
      end)

    # IO.inspect(updated_balance)

    {:reply, {:ok}, {pk, sk, blockchain, txn_list, updated_balance, indexed_blockchain}}
  end

  def handle_call(:get_txns, _from, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}) do
    {:reply, {txn_list}, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}}
  end

  def handle_call(
        :get_blockchain,
        _from,
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    {:reply, {blockchain}, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}}
  end

  def handle_call(
        :add_latest_block_to_indexded_blockchain,
        _from,
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    latest_block = Enum.at(blockchain, -1)
    latest_txns = latest_block.txns

    updated_indexed_blockchain =
      Enum.reduce(latest_txns, indexed_blockchain, fn txn, map ->
        if(Kernel.is_map(txn.message) == true) do
          if(txn.message.from =~ "miner") do
            {_, map} =
              Map.get_and_update(
                map,
                Bitcoin.Utility.string_to_atom(txn.message.to),
                fn current_value ->
                  if(current_value == nil) do
                    {current_value, txn.message.amount}
                  else
                    {current_value, current_value + txn.message.amount}
                  end
                end
              )

            map
          else
            {_, map} =
              Map.get_and_update(
                map,
                Bitcoin.Utility.string_to_atom(txn.message.to),
                fn current_value ->
                  if(current_value == nil) do
                    {current_value, txn.message.amount}
                  else
                    {current_value, current_value + txn.message.amount}
                  end
                end
              )

            map
          end
        else
          map
        end
      end)

    {:reply, {:ok}, {pk, sk, blockchain, txn_list, balance, updated_indexed_blockchain}}
  end

  def handle_cast(
        {:req_for_bitcoin, amount, req_hash},
        {pk, sk, blockchain, txn_list, balance, indexed_blockchain}
      ) do
    if(balance >= amount) do
      # Creating the new transaction
      txn_msg = %{
        amount: amount,
        from: "node_" <> Bitcoin.Utility.getHash(pk),
        to: "node_" <> req_hash
      }

      str_txn_msg = Bitcoin.Utility.txn_msg_to_string(txn_msg)

      signature_txn_msg = Bitcoin.Utility.sign(str_txn_msg, sk)

      txn = %{
        signature: signature_txn_msg,
        message: txn_msg,
        timestamp: System.system_time(),
        id: Bitcoin.Utility.getHash(signature_txn_msg)
      }

      # Updating the transaction list of every node
      updated_txn_list = txn_list ++ [txn]

      # Send new transaction to all
      [{_, all_nodes}] = :ets.lookup(:bitcoin, "nodes")

      my_hash = Bitcoin.Utility.getHash(pk)

      Enum.each(all_nodes, fn {hash} ->
        if(my_hash != hash) do
          GenServer.cast(
            Bitcoin.Utility.string_to_atom("node_" <> hash),
            {:add_txn, txn}
          )
        end
      end)

      {:noreply, {pk, sk, blockchain, updated_txn_list, balance - amount, indexed_blockchain}}
    else
      {:noreply, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}}
    end
  end

  def handle_cast({:add_txn, txn}, {pk, sk, blockchain, txn_list, balance, indexed_blockchain}) do
    updated_txns = txn_list ++ [txn]
    {:noreply, {pk, sk, blockchain, updated_txns, balance, indexed_blockchain}}
  end
end
