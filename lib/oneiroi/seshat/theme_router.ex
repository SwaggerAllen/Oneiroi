defmodule Oneiroi.Seshat.ThemeRouter do
  @moduledoc "The theme proposals' router (seshat#56): `theme-<resident_id>`."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.ThemeLedger",
    prefix: "theme-",
    commands: "Oneiroi.Seshat.Commands",
    dispatching: ~w(ProposeTheme AnswerTheme)
end
