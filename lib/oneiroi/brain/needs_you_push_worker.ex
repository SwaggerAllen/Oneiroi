defmodule Oneiroi.Brain.NeedsYouPushWorker do
  @moduledoc """
  The push for what waits on the witness (brain#77, gaia#26): each
  minute, over every active resident, her needs-you list is read as the
  Inbox reads it and handed to identity, which records on the witness's
  account the entries never pushed before and sends one content-free
  push for them. One push per entry, ever: the account aggregate keeps
  every entry it pushed for and answers a repeat with no event.

  A diff against what was pushed, not a hook on the events that make
  entries: the list is a projection over several systems' rows (brain
  #72), and an entry is made by whatever moves a row into a stage he
  holds, in any of them; a reading of the list itself is the one place
  every source already meets, and a source added later is pushed for
  with no change here.

  Her quiet hours hold: inside them nothing is read or recorded, so an
  entry that appeared then is pushed for at their end, once. The
  notifications question is never pushed for: a push can only reach a
  device, and a device subscribing answered it. Check-in reminders are
  not here; they stay opt-in.

  A cross-tenant job under the platform scope for the roster, named here
  (conventions §12); each resident's list is read under her own scope.
  Replay-safe: a second run in the same minute finds every entry pushed.
  """
  use Oneiroi.Worker, queue: :brain_needs_you, unique: [period: 30]

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Gaia
  alias Oneiroi.Sunna

  def run(_args) do
    if Gaia.push_config().enabled do
      for r <- AgathosDaimon.active_residents(),
          is_binary(r.account_id),
          do: push(r.id, r.account_id)
    end

    :ok
  end

  @doc "One resident's push, if any is due: `{:ok, pushed}`; public so a test can drive one by hand."
  @spec push(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def push(resident_id, account_id) do
    cond do
      Gaia.push_subscriptions(account_id) == [] ->
        {:ok, []}

      Sunna.quiet_now?(resident_id) ->
        {:ok, []}

      true ->
        entries =
          for e <- NeedsYou.list(resident_id),
              e.kind != NeedsYou.Notifications.kind(),
              do: %{"kind" => e.kind, "ref" => to_string(e.ref)}

        Gaia.push_needs_you(account_id, resident_id, entries)
    end
  end
end
