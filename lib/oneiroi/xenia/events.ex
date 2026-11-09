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
end
