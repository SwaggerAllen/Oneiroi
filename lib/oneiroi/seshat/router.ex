defmodule Oneiroi.Seshat.Router do
  @moduledoc "The library router: `library-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.Library",
    prefix: "library-",
    commands: "Oneiroi.Seshat.Commands",
    dispatching:
      ~w(WriteDocument RegisterKeepsake ArchiveDocument MoveDocument RemoveDocument AdoptDocument PublishPiece OpenDiscussion NoteKeepsake DispatchOracle AskResearch AnswerResearch FailResearch AnswerOracle FailOracle AskDigest AnswerDigest FailDigest)
end
