defmodule Oneiroi.Seshat.Commands do
  @moduledoc "The library aggregate's commands; `id` is the resident's id."

  defmodule WriteDocument do
    use Oneiroi.Command, fields: [:id, :path, :kind, :hash, :bytes]
  end

  defmodule RemoveDocument do
    # Seshat #33: a removable kind's document taken out of the library.
    use Oneiroi.Command, fields: [:id, :path, :kind]
  end

  defmodule AdoptDocument do
    # `provenance` is the originals import's (seshat #28), nil otherwise.
    use Oneiroi.Command, fields: [:id, :path, :kind, :hash, :bytes, :provenance]
  end

  defmodule PublishPiece do
    use Oneiroi.Command, fields: [:id, :path, :url]
  end

  defmodule NoteKeepsake do
    use Oneiroi.Command, fields: [:id, :path, :note]
  end

  defmodule OpenDiscussion do
    use Oneiroi.Command, fields: [:id, :path, :session_key]
  end

  # The oracle (brain #49, seshat #34): questions dispatched together,
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
end
