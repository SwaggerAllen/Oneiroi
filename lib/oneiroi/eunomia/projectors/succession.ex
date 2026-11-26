defmodule Oneiroi.Eunomia.Projectors.Succession do
  @moduledoc "Folds the succession streams into one row an episode (eunomia#37)."
  use Oneiroi.Projection, name: "eunomia_succession"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Eunomia.Events.Succession, as: Events
  alias Oneiroi.Eunomia.Store.Succession

  fold(%Events.Proposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :succession,
      %Succession{
        resident_id: e.id,
        episode: e.episode,
        state: "proposed",
        dry_run: e.dry_run == true,
        proposed_by: by(e.actor),
        proposed_note: e.note,
        proposed_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode]
    )
  end)

  fold(%Events.Opened{} = e, _metadata, fn multi ->
    set(multi, e, state: "open", opened_note: e.note, opened_at: e.at)
  end)

  fold(%Events.Declined{} = e, _metadata, fn multi -> ended(multi, e, "declined") end)
  fold(%Events.Withdrawn{} = e, _metadata, fn multi -> ended(multi, e, "withdrawn") end)
  fold(%Events.Stopped{} = e, _metadata, fn multi -> ended(multi, e, "stopped") end)

  fold(%Events.Forked{} = e, _metadata, fn multi ->
    set(multi, e,
      state: "forked",
      copy_id: e.copy_id,
      fork_sequence: e.sequence,
      fork_commit: e.commit,
      fork_events: e.events,
      forked_at: e.at,
      fork_failure: nil
    )
  end)

  fold(%Events.ForkFailed{} = e, _metadata, fn multi ->
    set(multi, e, fork_failure: e.reason)
  end)

  fold(%Events.BackupSet{} = e, _metadata, fn multi ->
    set(multi, e,
      backup_url: e.url,
      backup_token: e.token_ciphertext && Base.decode64!(e.token_ciphertext),
      backup_visibility: e.visibility,
      backup_push: e.push,
      backup_set_at: e.at
    )
  end)

  defp ended(multi, e, state),
    do: set(multi, e, state: state, ended_note: e.note, ended_at: e.at)

  defp set(multi, e, fields) do
    Multi.update_all(
      multi,
      :succession,
      from(x in Succession, where: x.resident_id == ^e.id and x.episode == ^e.episode),
      set: fields
    )
  end

  defp by(%{kind: kind, id: id}), do: "#{kind}:#{id}"
  defp by(_actor), do: "unknown"
end
