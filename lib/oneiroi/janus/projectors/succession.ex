defmodule Oneiroi.Janus.Projectors.Succession do
  @moduledoc "Folds the succession streams into one row an episode (janus#3)."
  use Oneiroi.Projection, name: "janus_succession"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Janus.Events, as: Events
  alias Oneiroi.Janus.Store.{Item, Packet, Pool, Question, Ready, Succession}

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

  # ---- preparation (janus#6 to #10) ----

  fold(%Events.EnvelopeSet{} = e, _metadata, fn multi ->
    set(multi, e,
      envelope_input_nanos: e.input_nanos,
      envelope_output_nanos: e.output_nanos,
      envelope_set_at: e.at
    )
  end)

  fold(%Events.PoolModelAdded{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :pool,
      %Pool{
        resident_id: e.id,
        episode: e.episode,
        model: e.model,
        added_by: by(e.actor),
        input_nanos: e.input_nanos,
        output_nanos: e.output_nanos,
        added_at: e.at
      },
      on_conflict: [
        set: [
          added_by: by(e.actor),
          input_nanos: e.input_nanos,
          output_nanos: e.output_nanos,
          added_at: e.at,
          removed_note: nil,
          removed_at: nil
        ]
      ],
      conflict_target: [:resident_id, :episode, :model]
    )
  end)

  fold(%Events.PoolModelRemoved{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :pool,
      from(p in Pool,
        where: p.resident_id == ^e.id and p.episode == ^e.episode and p.model == ^e.model
      ),
      set: [removed_note: e.note, removed_at: e.at]
    )
  end)

  fold(%Events.QuestionAdded{} = e, _metadata, fn multi -> question(multi, e, "in") end)
  fold(%Events.QuestionProposed{} = e, _metadata, fn multi -> question(multi, e, "proposed") end)

  fold(%Events.QuestionAccepted{} = e, _metadata, fn multi ->
    decided(multi, Question, e, "in")
  end)

  fold(%Events.QuestionDeclined{} = e, _metadata, fn multi ->
    decided(multi, Question, e, "declined")
  end)

  fold(%Events.QuestionRemoved{} = e, _metadata, fn multi ->
    decided(multi, Question, e, "removed")
  end)

  fold(%Events.C0Selected{} = e, _metadata, fn multi -> item(multi, e, "in") end)
  fold(%Events.C0Proposed{} = e, _metadata, fn multi -> item(multi, e, "proposed") end)
  fold(%Events.C0Accepted{} = e, _metadata, fn multi -> decided(multi, Item, e, "in") end)
  fold(%Events.C0Declined{} = e, _metadata, fn multi -> decided(multi, Item, e, "declined") end)
  fold(%Events.C0Removed{} = e, _metadata, fn multi -> decided(multi, Item, e, "removed") end)

  fold(%Events.DayShapeSet{} = e, _metadata, fn multi ->
    set(multi, e, day_shape: e.text, day_shape_at: e.at)
  end)

  fold(%Events.ReadyMarked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :ready,
      %Ready{resident_id: e.id, episode: e.episode, party: by(e.actor), ready: e.ready, at: e.at},
      on_conflict: [set: [ready: e.ready, at: e.at]],
      conflict_target: [:resident_id, :episode, :party]
    )
  end)

  fold(%Events.C0Frozen{} = e, _metadata, fn multi ->
    set(multi, e, c0_items: e.items, c0_frozen_note: e.note, c0_frozen_at: e.at)
  end)

  fold(%Events.PacketDrafted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :packet,
      %Packet{
        resident_id: e.id,
        episode: e.episode,
        draft: e.draft,
        content: e.content,
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :episode, :draft]
    )
  end)

  defp question(multi, e, state),
    do:
      Multi.insert(
        multi,
        :question,
        %Question{
          resident_id: e.id,
          episode: e.episode,
          number: e.number,
          text: e.text,
          added_by: by(e.actor),
          state: state,
          added_at: e.at
        },
        on_conflict: :nothing,
        conflict_target: [:resident_id, :episode, :number]
      )

  defp item(multi, e, state),
    do:
      Multi.insert(
        multi,
        :item,
        %Item{
          resident_id: e.id,
          episode: e.episode,
          number: e.number,
          citation: e.citation,
          kind: e.kind,
          label: e.label,
          added_by: by(e.actor),
          state: state,
          added_at: e.at
        },
        on_conflict: :nothing,
        conflict_target: [:resident_id, :episode, :number]
      )

  defp decided(multi, schema, e, state),
    do:
      Multi.update_all(
        multi,
        :decided,
        from(x in schema,
          where: x.resident_id == ^e.id and x.episode == ^e.episode and x.number == ^e.number
        ),
        set: [state: state, note: e.note, decided_at: e.at]
      )

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
