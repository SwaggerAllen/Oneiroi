defmodule Oneiroi.Seshat.PiecesRouter do
  @moduledoc "The pieces aggregate's router (seshat#42): `pieces-<resident_id>`, a piece's review and draft."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.Pieces",
    prefix: "pieces-",
    commands: "Oneiroi.Seshat.Commands",
    dispatching: ~w(ReviewPiece DraftPiece)
end
