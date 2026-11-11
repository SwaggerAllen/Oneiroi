defmodule Oneiroi.Brain.NeedsYou.Notifications do
  @moduledoc """
  The notifications question (brain#76, gaia#25): while the witness's
  account has not answered whether his devices may be told when
  something waits on him, the question waits on him. "No thanks" answers
  it, and so does a device subscribing, from the bell or later from
  Settings. Asked only when pushes can be sent at all.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.NeedsYou.Entry
  alias Oneiroi.Gaia

  @doc "The entry kind, which the push (brain#77) and the check-in leave out."
  @spec kind() :: String.t()
  def kind, do: "notifications"

  @impl true
  def stages, do: [%{kind: kind(), screen: "settings"}]

  @impl true
  def entries(resident_id) do
    with {:ok, %{account_id: account_id} = resident} when is_binary(account_id) <-
           AgathosDaimon.fetch(resident_id),
         %{enabled: true} <- Gaia.push_config(),
         nil <- Gaia.push_answer(account_id) do
      [
        %Entry{
          kind: kind(),
          ref: "push",
          since: resident.created_at || Clock.now(),
          screen: "settings",
          about: %{}
        }
      ]
    else
      _answered_or_unasked -> []
    end
  end
end
