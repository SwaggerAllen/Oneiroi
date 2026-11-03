defmodule Oneiroi.Seshat.Events do
  @moduledoc """
  The library stream's events (spec §3.1, §6.5):
  `library-<resident_id>`, one per resident. The file is the record and
  lives in the repository; the event is its provenance: that it was
  written through the flow or adopted from outside it, its hash and its
  size, by whom, never its content.
  """

  defmodule DocumentWritten do
    use Oneiroi.Event, version: 1, fields: [:id, :path, :kind, :hash, :bytes]
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
    # library (seshat #33), by whom: the file leaves the repository and
    # the event is what stays of it, never its content.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :kind]
  end

  defmodule PiecePublished do
    use Oneiroi.Event, version: 1, fields: [:id, :path, :url]
  end

  defmodule KeepsakeNoted do
    # Why a keepsake mattered, in the resident's words (seshat #32): what
    # a pin carries for a bookmark, beside a gift that is never edited.
    # The latest stands; the earlier ones stay on the stream.
    use Oneiroi.Event, version: 1, fields: [:id, :path, :note]
  end

  defmodule DiscussionOpened do
    # A session linked to a piece (`writing_discuss`, spec §8).
    use Oneiroi.Event, version: 1, fields: [:id, :path, :session_key]
  end

  defmodule OracleDispatched do
    # One question put to the oracle (brain #49, seshat #34): named at
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
end
