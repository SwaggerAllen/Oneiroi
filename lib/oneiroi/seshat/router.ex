defmodule Oneiroi.Seshat.Router do
  @moduledoc "The library router: `library-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.Library",
    prefix: "library-",
    commands: "Oneiroi.Seshat.Commands",
    dispatching:
      ~w(WriteDocument RemoveDocument AdoptDocument PublishPiece OpenDiscussion NoteKeepsake DispatchOracle AnswerOracle FailOracle)
end
