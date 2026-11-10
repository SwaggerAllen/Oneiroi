defmodule Oneiroi.Seshat.Events do
  @moduledoc """
  The library stream's events (spec §3.1, §6.5):
  `library-<resident_id>`, one per resident. The file is the record and
  lives in the repository; the event is its provenance: that it was
  written through the flow or adopted from outside it, its hash and its
  size, by whom, never its content.
  """

  defmodule DocumentWritten do
    # Version 2 adds `note` (seshat#54): what the writer said of this
    # version, a restore's "restored from" among them, shown in the
    # document's versions; nil on every version 1 write, which the
    # identity upcaster leaves as the struct's default.
    use Oneiroi.Event, version: 2, fields: [:id, :path, :kind, :hash, :bytes, :note]
  end

  defimpl Commanded.Event.Upcaster, for: Oneiroi.Seshat.Events.DocumentWritten do
    def upcast(event, _metadata), do: event
  end

  defmodule DocumentAdopted do
    # A file made outside the flow (F27), registered as it was found.
    # Version 2 adds `provenance`, where an original came from (seshat
    # #28): `%{source, commit, path, blob}`, the source repository's URL
    # without userinfo, the pinned commit, the path there and the git
    # blob sha the copy was verified against; nil for every other
    # adoption, which is what a version 1 event upcasts to.
    use Oneiroi.Event, version: 2, fields: [:id, :path, :kind, :hash, :bytes, :provenance]
  end

  defimpl Commanded.Event.Upcaster, for: Oneiroi.Seshat.Events.DocumentAdopted do
    def upcast(event, _metadata), do: event
  end

  defmodule DocumentRemoved do
    # A document of a removable kind (scratch, human) taken out of the
    # library (seshat#33), by whom: the file leaves the repository and
    # the event is what stays of it, never its content.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :kind]
  end

  defmodule DocumentMoved do
    # A document moved from one path, and so one kind, to another
    # (seshat#39), by whom, its bytes unchanged: the move is the record
    # of where it was, and a citation of the old path follows it.
    use Oneiroi.Event, version: 1, fields: [:id, :from, :to, :from_kind, :to_kind, :hash]
  end

  defmodule PiecePublished do
    use Oneiroi.Event, version: 1, fields: [:id, :path, :url]
  end

  defmodule DocumentArchived do
    # A document archived (seshat#45): its words moved whole to `to`
    # under frontmatter (who, when, why), and a tombstone left at the old
    # path naming where it went and why, so a citation still resolves.
    use Oneiroi.Event,
      version: 1,
      fields: [
        :id,
        :path,
        :to,
        :why,
        :archived_hash,
        :archived_bytes,
        :tombstone_hash,
        :tombstone_bytes
      ]
  end

  defmodule KeepsakeRegistered do
    # A root file made a keepsake (seshat#44): a deliberate act, by
    # either party; from then it is never written again.
    use Oneiroi.Event, version: 1, fields: [:id, :path]
  end

  defmodule KeepsakeNoted do
    # Why a keepsake mattered, in the resident's words (seshat#32): what
    # a pin carries for a bookmark, beside a gift that is never edited.
    # The latest stands; the earlier ones stay on the stream.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :note]
  end

  defmodule DiscussionOpened do
    # A session linked to a piece (`writing_discuss`, spec §8).
    use Oneiroi.Event, version: 1, fields: [:id, :path, :session_key]
  end

  defmodule OracleDispatched do
    # One question put to the oracle (brain#49, seshat#34): named at
    # dispatch, never "find something interesting", with the sources it
    # is to read beside her whole memory, and the conversation that
    # asked, which is told when it lands. The actor says who asked.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :question, :sources, :session_key]
  end

  defmodule OracleAnswered do
    # The answer, written at `path` under oracle/, with the confidence
    # it stated; `model` is the instance that read, from the actor.
    # `read`: every source it read (named and opened by its tools);
    # `used`: what its answer says it drew on; both in citation form.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :path, :confidence, :read, :used, :model]
  end

  defmodule OracleFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :reason]
  end

  defmodule ResearchAsked do
    # A question for the reader's research pass (seshat#38): named,
    # with the pages to start from, by whoever the actor is, and the
    # conversation told when it lands.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :question, :urls, :session_key]
  end

  defmodule ResearchAnswered do
    # The notes written under `path` (research/<number>-<slug>/), and the
    # pages they came from.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :path, :sources]
  end

  defmodule ResearchFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :reason]
  end

  defmodule ExternalCommissioned do
    # A source outside the house, commissioned for citing (seshat#46):
    # `kind` web or doc, `key` what a citation names it by (a web page's
    # URL digest; a document's provider/owner/repo/path), `url` where it
    # is fetched from, `ref` a document's branch or HEAD.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :kind, :key, :url, :ref, :session_key]
  end

  defmodule ExternalFetchAsked do
    # A fresh copy asked of the reader, and the conversation told when it lands.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :session_key]
  end

  defmodule ExternalFetched do
    # The copy the reader brought, written at `path`: its title, the
    # digest of its words, a document's commit, its size.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :path, :title, :content_hash, :commit, :bytes]
  end

  defmodule ExternalFetchFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :reason]
  end

  defmodule DigestAsked do
    # A digest asked of the reader (seshat#40): what reached the
    # resident's streams (her mail's newsletters and posts) since `since`,
    # by whoever the actor is, and the conversation told when it lands.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :session_key, :since],
      instants: [:since]
  end

  defmodule DigestAnswered do
    # The digest written at `path` (feeds/digests/<number>-<day>.md), and
    # how many items it covered.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :path, :items]
  end

  defmodule DigestFailed do
    use Oneiroi.Event, version: 1, fields: [:id, :number, :reason]
  end

  defmodule PieceReviewed do
    # The witness's answer to a piece she marked for review (seshat#42):
    # approve or decline, with a note, of the version with this hash.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :decision, :hash], decision: true
  end

  defmodule PieceDrafted do
    # The reader made a Substack draft of an approved piece (seshat#42);
    # the witness presses Publish there himself.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :draft_url]
  end

  defmodule KindDefined do
    # A kind of the resident's own (seshat#51), either party's: its
    # descriptor, checked against the safe subset, the file in its folder
    # written beside it.
    use Oneiroi.Event, version: 1, fields: [:id, :kind, :descriptor, :note]
  end

  defmodule KindChanged do
    # A user kind's descriptor rewritten whole (seshat#51), either party's.
    use Oneiroi.Event, version: 1, fields: [:id, :kind, :descriptor, :note]
  end

  defmodule KindGateProposed do
    # A system kind's gate proposed off, away from safety (seshat#51): the
    # other party answers. Numbered by the stream.
    use Oneiroi.Event,
      version: 1,
      fields: [:id, :number, :kind, :approvable],
      decision: true
  end

  defmodule KindGateAnswered do
    # The other party's answer to a gate proposal (seshat#51), with a note.
    use Oneiroi.Event, version: 1, fields: [:id, :number, :agree], decision: true
  end

  defmodule KindGateMoved do
    # A system kind's gate as it now stands for the resident (seshat#51):
    # back on by either party alone, off only by an agreed proposal
    # (`number`).
    use Oneiroi.Event, version: 1, fields: [:id, :kind, :approvable, :number]
  end
end
