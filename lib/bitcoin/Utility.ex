defmodule Bitcoin.Utility do
  def getHash(string) do
    :crypto.hash(:sha, string) |> Base.encode16() |> String.downcase()
  end

  def sign(string, skey) do
    {:ok, signature} = RsaEx.sign(string, skey)
    signature
  end

  def string_to_atom(string) do
    String.to_atom(string)
  end

  def txn_msg_to_string(txn_msg) do
    to_string(txn_msg.from) <> to_string(txn_msg.to) <> to_string(txn_msg.amount)
  end

  def combine(txn_set) do
    str_txn_set =
      Enum.reduce(txn_set, "", fn txn, str ->
        msg = txn.message

        str_msg =
          if(is_map(msg)) do
            to_string(msg.from) <> to_string(msg.to) <> to_string(msg.amount)
          else
            msg
          end

        str_signature = txn.signature |> Base.encode16() |> String.downcase()
        str_timestamp = to_string(txn.timestamp)
        str_txn = str_msg <> str_signature <> str_timestamp
        str <> str_txn
      end)

    str_txn_set
  end

  def verify(string, signature, pk) do
    {:ok, valid} = RsaEx.verify(string, signature, pk)
    valid
  end
end
