defmodule Oneiroi.Sunna.QueueRouter do
  @moduledoc "The house queue aggregate's router (sunna#80): `queue-<household_id>`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Sunna.Queue",
    prefix: "queue-",
    commands: "Oneiroi.Sunna.QueueCommands",
    dispatching:
      ~w(OpenProject CloseProject DefineTemplate OpenTask TakeActivity FinishActivity SkipActivity BlockActivity ReopenActivity FailActivity AssignActivity DecideReview DropTask FillSlot RouteClaudeCode CutOver CutBack)
end
