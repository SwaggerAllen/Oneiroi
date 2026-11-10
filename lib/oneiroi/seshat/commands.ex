defmodule Oneiroi.Seshat.Commands do
  @moduledoc "The library aggregate's commands; `id` is the resident's id."

  defmodule WriteDocument do
    # `note` (seshat#54): what the writer said of this version, or nil.
    use Oneiroi.Command, fields: [:id, :path, :kind, :hash, :bytes, :note]
  end

  defmodule MoveDocument do
    # Seshat #39: a document taken from one path, and so one kind, to
    # another, its bytes unchanged (`hash` is what they hash to).
    use Oneiroi.Command, fields: [:id, :from, :to, :from_kind, :to_kind, :hash]
  end

  defmodule RemoveDocument do
    # Seshat #33: a removable kind's document taken out of the library.
    use Oneiroi.Command, fields: [:id, :path, :kind]
  end

  defmodule AdoptDocument do
    # `provenance` is the originals import's (seshat#28), nil otherwise.
    use Oneiroi.Command, fields: [:id, :path, :kind, :hash, :bytes, :provenance]
  end

  defmodule PublishPiece do
    use Oneiroi.Command, fields: [:id, :path, :url]
  end

  defmodule ArchiveDocument do
    use Oneiroi.Command,
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

  defmodule RegisterKeepsake do
    use Oneiroi.Command, fields: [:id, :path]
  end

  defmodule NoteKeepsake do
    use Oneiroi.Command, fields: [:id, :path, :note]
  end

  defmodule OpenDiscussion do
    use Oneiroi.Command, fields: [:id, :path, :session_key]
  end

  # The oracle (brain#49, seshat#34): questions dispatched together,
  # each numbered from the library's oracle sequence; `questions` are
  # `%{question, sources}`, `session_key` the conversation that asked.
  defmodule DispatchOracle do
    use Oneiroi.Command, fields: [:id, :questions, :session_key]
  end

  defmodule AnswerOracle do
    use Oneiroi.Command, fields: [:id, :number, :path, :confidence, :read, :used]
  end

  defmodule FailOracle do
    use Oneiroi.Command, fields: [:id, :number, :reason]
  end

  # Research (seshat#38): a question for the reader's research pass,
  # with the pages to start from; numbered from the library's research
  # sequence; `session_key` is the conversation told when it lands.
  defmodule AskResearch do
    use Oneiroi.Command, fields: [:id, :question, :urls, :session_key]
  end

  defmodule AnswerResearch do
    use Oneiroi.Command, fields: [:id, :number, :path, :sources]
  end

  defmodule FailResearch do
    use Oneiroi.Command, fields: [:id, :number, :reason]
  end

  # External sources (seshat#46): a web page or a repository's document,
  # commissioned by either party, fetched by the reader on demand.
  defmodule CommissionExternal do
    use Oneiroi.Command, fields: [:id, :kind, :key, :url, :ref, :session_key]
  end

  defmodule AskExternalFetch do
    use Oneiroi.Command, fields: [:id, :number, :session_key]
  end

  defmodule RecordExternalFetch do
    use Oneiroi.Command, fields: [:id, :number, :path, :title, :content_hash, :commit, :bytes]
  end

  defmodule FailExternalFetch do
    use Oneiroi.Command, fields: [:id, :number, :reason]
  end

  defmodule AskDigest do
    # Seshat #40: a digest of the reader's streams since `since`.
    use Oneiroi.Command, fields: [:id, :session_key, :since]
  end

  defmodule AnswerDigest do
    use Oneiroi.Command, fields: [:id, :number, :path, :items]
  end

  defmodule FailDigest do
    use Oneiroi.Command, fields: [:id, :number, :reason]
  end

  # A writing piece's review (seshat#42), on `pieces-<resident_id>`.
  defmodule ReviewPiece do
    use Oneiroi.Command, fields: [:id, :path, :decision, :note, :hash]
  end

  defmodule DraftPiece do
    use Oneiroi.Command, fields: [:id, :path, :draft_url]
  end

  # A resident's own kinds and the system kinds' gates (seshat#51), on
  # `kinds-<resident_id>`.
  defmodule DefineKind do
    use Oneiroi.Command, fields: [:id, :kind, :descriptor, :note]
  end

  defmodule ProposeKindGate do
    use Oneiroi.Command, fields: [:id, :kind, :approvable, :note]
  end

  defmodule AnswerKindGate do
    use Oneiroi.Command, fields: [:id, :number, :agree, :note]
  end

  defmodule ProposeTheme do
    # seshat#56: her three seeds, checked before they get here.
    use Oneiroi.Command, fields: [:id, :ground, :resident, :witness], decision: true
  end

  defmodule AnswerTheme do
    # seshat#56: the witness accepts or declines her proposal, with a note.
    use Oneiroi.Command, fields: [:id, :number, :agree], decision: true
  end
end
