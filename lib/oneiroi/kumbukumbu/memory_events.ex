defmodule Oneiroi.Kumbukumbu.Events.Memory do
  @moduledoc """
  The memory stream's events, version 1: `memory-<resident_id>`, one per
  resident, holding its bookmarks, their pins and spans, the closed tag
  set and the taggings across every record kind (spec §3.1, §6.3). The
  stream is memory's own where the spec drew it within the resident's,
  for the reason `systems/kumbukumbu.md` #19 gives.

  A bookmark's `number` is minted by the resident aggregate
  (`Oneiroi.AgathosDaimon.mint_id/3`), so `lily:bookmark/42` survives a
  rebuild; an actor carried as a field (`proposed_by`) is a map of kind,
  id and model, the same shape the event's own `actor` takes on the wire.
  """

  defmodule BookmarkAdded do
    # The resident's words about why a moment mattered (spec §6.3): a
    # line of at most 120 characters, a summary, the turn it was in
    # (`anchor_ref`, `anchor_at`) and a span of `turns_back` turns ending
    # there. `proposal_ref` and `proposed_by` are set when the witness
    # proposed it; the words are still the resident's.
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :number,
        :session_key,
        :anchor_ref,
        :anchor_at,
        :turns_back,
        :line,
        :summary,
        :proposal_ref,
        :proposed_by
      ],
      instants: [:anchor_at]
  end

  defmodule BookmarkExtended do
    # A scene is rarely known to be one at its start: the span grows
    # later, as an event, rather than a second bookmark being made.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :turns_back]
  end

  defmodule BookmarkPinned do
    # A pin is a decision trace, never a measurement (spec §6.3); the
    # actor is who pinned, which the row shows as `pinned_by`.
    use Oneiroi.Event, version: 1, fields: [:id, :number]
  end

  defmodule BookmarkUnpinned do
    use Oneiroi.Event, version: 1, fields: [:id, :number]
  end

  defmodule BookmarkProposed do
    # The witness may propose a bookmark with a suggested line and never
    # author one (spec §6.3); the note is what the resident reads first.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :ref, :session_key, :anchor_ref, :line]
  end

  defmodule BookmarkProposalDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :ref]
  end

  defmodule TagProposed do
    # Either party proposes; only the witness decides the set.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :slug]
  end

  defmodule TagApproved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :slug]
  end

  defmodule TagRejected do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :slug]
  end

  defmodule TagCreated do
    # The witness adds a tag to the set directly.
    use Oneiroi.Event, version: 1, fields: [:id, :slug]
  end

  defmodule TagRetired do
    # Retiring never removes a tagging: the rows that carried the tag
    # keep it, and the tag stops being applicable.
    use Oneiroi.Event, version: 1, fields: [:id, :slug]
  end

  defmodule TagApplied do
    # One tagging names a tag and a target of any record kind (spec
    # §6.3): `target_kind` is `bookmark`, `conversation` or `turn` in
    # this slice; `target_id` the bookmark's number, the session key or
    # the turn ref.
    use Oneiroi.Event, version: 1, fields: [:id, :slug, :target_kind, :target_id]
  end

  defmodule TaggingRemoved do
    use Oneiroi.Event, version: 1, fields: [:id, :slug, :target_kind, :target_id]
  end

  defmodule BehaviourDefined do
    # A behaviour is a row the resident owns (spec §6.3, F55): a name in
    # its own words, the trigger it answers (a map of `words`, `tags` and
    # `times`, any of which matching is a match), and a stance, `keep` or
    # `change`. `number` is the resident's own sequence.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :name, :trigger, :stance]
  end

  defmodule BehaviourChanged do
    # Revision adds, it does not overwrite: the new words, trigger and
    # stance, with the old ones still in the log.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :name, :trigger, :stance]
  end

  defmodule BehaviourAffirmed do
    # "I like when you do that": the witness's, with a note, part of the
    # connection score and never of the habit score.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule BehaviourEnacted do
    # The tagging that says "this was one": on a turn or a bookmark, by
    # the resident's actor at turn time. Nothing enters a behaviour's
    # record without the resident's actor on it.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :target_kind, :target_id]
  end

  defmodule RevisionProposed do
    # Revision (spec §6.3, F13): a stance is revised only with the
    # resident's agreement, so the witness's revision of one is a
    # proposal with its reason as the note (kumbukumbu #30).
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :number, :target_kind, :target_id, :kind, :text]
  end

  defmodule RevisionApplied do
    # A correction that holds: a fact by either party, a stance by the
    # resident, or a proposal the resident accepted; the note is the
    # reason, or the acceptance's. Revision adds and never overwrites:
    # the target's words stand and the revision sits beside them.
    use Oneiroi.Event,
      version: 1,
      decision: true,
      fields: [:id, :number, :target_kind, :target_id, :kind, :text]
  end

  defmodule RevisionDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end
end
