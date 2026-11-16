defmodule Oneiroi.Xenia.Events do
  @moduledoc """
  The correspondence stream's events, version 1 (spec §6.6, F23 as
  amended 2026-11-02): `xenia-<resident_id>`, one per resident. Third
  parties arrive as `CorrespondenceReceived` and reach the resident at
  once, unless their identity is blocked, when only the fact of them is
  kept and never their words; the resident's replies are drafts the
  witness approves before anything is sent, and a send leaves a receipt.
  """

  defmodule CorrespondenceReceived do
    # `blocked` is the block rule's answer at receipt: a blocked sender's
    # message keeps its address and id (so a second delivery is still a
    # duplicate) and loses its name, subject and words, which are nil.
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :number,
        :platform,
        :account,
        :external_id,
        :sender,
        :sender_name,
        :verified,
        :thread,
        :subject,
        :text,
        :sent_at,
        :blocked
      ],
      instants: [:sent_at]
  end

  defmodule CorrespondenceMarked do
    # The resident has read these (the seen mark).
    use Oneiroi.Event, version: 1, fields: [:id, :numbers]
  end

  defmodule CorrespondentBlocked do
    # The actor is who blocked: the resident or the witness.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :platform, :identity, :name]
  end

  defmodule CorrespondentUnblocked do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :platform, :identity]
  end

  defmodule ReplyDrafted do
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :in_reply_to, :platform, :account, :thread, :to, :text]
  end

  defmodule ReplySuperseded do
    # A draft the resident replaced with a newer one (xenia#17): `number`
    # is the old draft, `by` the new; the old leaves the witness's queue
    # and is kept.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :by]
  end

  defmodule ReplyApproved do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule ReplyDeclined do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :number]
  end

  defmodule ReplyMarkedSent do
    # The receipt: who sent it (the actor), and where it now is, if the
    # platform gives it an address.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :url]
  end

  defmodule ReaderSitesSet do
    # The reader's two allowlists as the witness set them (xenia#16).
    use Oneiroi.Event, version: 1, fields: [:id, :scrape, :research]
  end

  defmodule RouteDefined do
    # A route of the resident's own (xenia#19), either party's: its
    # descriptor, checked against the safe subset, its file written
    # under routes/.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :descriptor, :note]
  end

  defmodule RouteChanged do
    # A route of hers rewritten whole (xenia#19), either party's.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :descriptor, :note]
  end

  defmodule RouteAsked do
    # A run of a route of hers asked, either party's (xenia#19): the
    # reader fires it and its rows land as `<kind>/<key>-<number>.md`.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :number, :note]
  end

  defmodule RouteLanded do
    # A run's reading landed (xenia#19), as the document at `path`.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :path]
  end

  defmodule RouteFailed do
    # A run the reader could not do (xenia#19), and why.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :reason]
  end

  defmodule ProfileSet do
    # A profile the witness made or named (xenia#19): one origin, whom
    # it is signed in as. Never exported: credentials have one home.
    use Oneiroi.Event, version: 1, fields: [:id, :key, :profile, :note]
  end

  defmodule ProfileRevoked do
    # The witness revoked a profile (xenia#19): its routes stay, unable
    # to fire, until it is restored.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :key]
  end

  defmodule ProfileRestored do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :key]
  end

  # ---- presence (xenia#20), on `presence-<resident_id>` ----

  defmodule PresenceSet do
    # The witness's switch, and the Substack handle whose public
    # subscriptions the rotation reads.
    use Oneiroi.Event, version: 1, fields: [:id, :enabled, :handle]
  end

  defmodule FollowsRecorded do
    # The follow list as fetched: each account's key (its subdomain),
    # name, host, publication and author ids; `visible` the count the
    # profile claims, which the list was checked against.
    use Oneiroi.Event, version: 1, fields: [:id, :accounts, :visible]
  end

  defmodule AccountExcluded do
    # A mask, not a deletion: the follow stays; the rotation passes over
    # it. The note is the one-line reason, dated by the event.
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :key]
  end

  defmodule AccountIncluded do
    use Oneiroi.Event, version: 1, decision: true, fields: [:id, :key]
  end

  defmodule PassDrawn do
    # A day's pass: the accounts sampled from the cursor, how many items
    # their pool held, the two read cuts' sizes, the outbound cap, and the
    # items to read, each with its account, kind, url, counts and cut.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :day, :accounts, :pool, :ranked, :serendipity, :cap, :reads]
  end

  defmodule ItemRead do
    # Read whole by the resident: what earns an interaction.
    use Oneiroi.Event, version: 1, fields: [:id, :pass, :item]
  end

  defmodule InteractionStaged do
    # A like, a comment or a restack, for an item read this pass; `text`
    # is a comment's words; `supersedes` the one it revises.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :pass, :item, :account, :kind, :text, :supersedes]
  end

  defmodule InteractionDecided do
    # The witness's call: `approve` (with the instant it may go out,
    # jittered), `revise` or `pass`, with his comment if he gave one.
    use Oneiroi.Event,
      version: 1,
      instants: [:release_at],
      fields: [:id, :number, :decision, :comment, :release_at]
  end

  defmodule InteractionSent do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :url]
  end

  defmodule InteractionFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :reason]
  end
end
