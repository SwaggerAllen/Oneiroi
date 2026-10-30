defmodule Oneiroi.Kumbukumbu.Projectors.Memory do
  @moduledoc "Folds the memory streams into bookmarks, proposals, tags and taggings."
  use Oneiroi.Projection, name: "kumbukumbu_memory"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Kumbukumbu.Events.Memory, as: Events
  alias Oneiroi.Kumbukumbu.Store.{Bookmark, BookmarkProposal, Revision, Tag, Tagging}

  fold(%Events.BookmarkAdded{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :bookmark,
      %Bookmark{
        resident_id: e.id,
        number: e.number,
        session_key: e.session_key,
        anchor_ref: e.anchor_ref,
        anchor_at: e.anchor_at,
        turns_back: e.turns_back,
        line: e.line,
        summary: e.summary,
        added_by_kind: actor_field(e.actor, :kind),
        added_by_id: actor_field(e.actor, :id),
        added_by_model: actor_field(e.actor, :model),
        proposed_by_kind: actor_field(e.proposed_by, :kind),
        proposed_by_id: actor_field(e.proposed_by, :id),
        created_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
    |> accept_proposal(e)
  end)

  fold(%Events.BookmarkExtended{} = e, _metadata, fn multi ->
    set_bookmark(multi, e.number, turns_back: e.turns_back)
  end)

  fold(%Events.BookmarkPinned{} = e, _metadata, fn multi ->
    set_bookmark(multi, e.number,
      pinned_by_kind: actor_field(e.actor, :kind),
      pinned_by_id: actor_field(e.actor, :id),
      pinned_at: e.at
    )
  end)

  fold(%Events.BookmarkUnpinned{} = e, _metadata, fn multi ->
    set_bookmark(multi, e.number, pinned_by_kind: nil, pinned_by_id: nil, pinned_at: nil)
  end)

  fold(%Events.BookmarkProposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :proposal,
      %BookmarkProposal{
        resident_id: e.id,
        ref: e.ref,
        session_key: e.session_key,
        anchor_ref: e.anchor_ref,
        line: e.line,
        note: e.note,
        proposed_by_kind: actor_field(e.actor, :kind),
        proposed_by_id: actor_field(e.actor, :id),
        proposed_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :ref]
    )
  end)

  fold(%Events.BookmarkProposalDeclined{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :declined,
      from(p in BookmarkProposal, where: p.ref == ^e.ref),
      set: [state: "declined", decided_note: e.note, decided_at: e.at]
    )
  end)

  fold(%Events.RevisionProposed{} = e, _metadata, fn multi ->
    put_revision(multi, e, "proposed")
  end)

  # Applied straight, or applied from a proposal: the row keeps the
  # proposal's reason as `note` and takes the acceptance as the decision.
  fold(%Events.RevisionApplied{} = e, _metadata, fn multi ->
    multi
    |> put_revision(multi_key(e), e, "applied")
    |> Multi.update_all(
      {:accepted, e.number},
      from(r in Revision, where: r.number == ^e.number and r.state == "proposed"),
      set: [state: "applied", decided_at: e.at, decision_note: e.note]
    )
  end)

  fold(%Events.RevisionDeclined{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :declined_revision,
      from(r in Revision, where: r.number == ^e.number),
      set: [state: "declined", decided_at: e.at, decision_note: e.note]
    )
  end)

  fold(%Events.TagProposed{} = e, _metadata, fn multi ->
    put_tag(multi, e, "proposed", e.note)
  end)

  fold(%Events.TagApproved{} = e, _metadata, fn multi ->
    set_tag(multi, e.slug, state: "active", decided_at: e.at)
  end)

  fold(%Events.TagRejected{} = e, _metadata, fn multi ->
    set_tag(multi, e.slug, state: "rejected", decided_at: e.at)
  end)

  fold(%Events.TagCreated{} = e, _metadata, fn multi ->
    put_tag(multi, e, "active", nil)
  end)

  fold(%Events.TagRetired{} = e, _metadata, fn multi ->
    set_tag(multi, e.slug, state: "retired", decided_at: e.at)
  end)

  fold(%Events.TagApplied{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :tagging,
      %Tagging{
        resident_id: e.id,
        tag: e.slug,
        target_kind: e.target_kind,
        target_id: to_string(e.target_id),
        applied_by_kind: actor_field(e.actor, :kind),
        applied_by_id: actor_field(e.actor, :id),
        applied_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :tag, :target_kind, :target_id]
    )
  end)

  fold(%Events.TaggingRemoved{} = e, _metadata, fn multi ->
    id = to_string(e.target_id)

    Multi.delete_all(
      multi,
      :untagged,
      from(t in Tagging,
        where: t.tag == ^e.slug and t.target_kind == ^e.target_kind and t.target_id == ^id
      )
    )
  end)

  defp accept_proposal(multi, %{proposal_ref: nil}), do: multi

  defp accept_proposal(multi, e) do
    Multi.update_all(
      multi,
      :accepted,
      from(p in BookmarkProposal, where: p.ref == ^e.proposal_ref),
      set: [state: "accepted", bookmark_number: e.number, decided_at: e.at]
    )
  end

  defp set_bookmark(multi, number, set),
    do:
      Multi.update_all(multi, :bookmark, from(b in Bookmark, where: b.number == ^number),
        set: set
      )

  defp set_tag(multi, slug, set),
    do: Multi.update_all(multi, :tag, from(t in Tag, where: t.slug == ^slug), set: set)

  # A tag re-proposed or re-created after a rejection or retirement
  # takes the row over: one row per slug, in its latest state.
  defp put_tag(multi, e, state, note) do
    Multi.insert(
      multi,
      :tag,
      %Tag{
        resident_id: e.id,
        slug: e.slug,
        state: state,
        proposed_by_kind: actor_field(e.actor, :kind),
        proposed_by_id: actor_field(e.actor, :id),
        note: note,
        created_at: e.at
      },
      on_conflict: [
        set: [
          state: state,
          note: note,
          proposed_by_kind: actor_field(e.actor, :kind),
          proposed_by_id: actor_field(e.actor, :id),
          created_at: e.at,
          decided_at: nil
        ]
      ],
      conflict_target: [:resident_id, :slug]
    )
  end

  # An actor on a replayed event has string keys; one on a fresh event is
  # the struct. Both are one actor.
  defp actor_field(%{} = actor, key) do
    case Map.get(actor, key) || Map.get(actor, Atom.to_string(key)) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp actor_field(_other, _key), do: nil

  defp put_revision(multi, e, state), do: put_revision(multi, {:revision, e.number}, e, state)

  defp put_revision(multi, key, e, state) do
    Multi.insert(
      multi,
      key,
      %Revision{
        resident_id: e.id,
        number: e.number,
        target_kind: e.target_kind,
        target_id: e.target_id,
        kind: e.kind,
        text: e.text,
        note: e.note,
        state: state,
        by_kind: actor_field(e.actor, :kind),
        by_id: actor_field(e.actor, :id),
        at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end

  defp multi_key(e), do: {:revision, e.number}
end
