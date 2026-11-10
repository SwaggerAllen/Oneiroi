defmodule Oneiroi.Seshat.SceneRouter do
  @moduledoc "The scenes router: `scenes-<resident_id>` (seshat#52)."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.Scene",
    prefix: "scenes-",
    commands: "Oneiroi.Seshat.SceneCommands",
    dispatching: ~w(WriteScene CorrectScene CorrectSceneSummary CloseScenes)
end
