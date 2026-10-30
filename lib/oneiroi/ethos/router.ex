defmodule Oneiroi.Ethos.Router do
  @moduledoc "The character aggregate's router: `ethos-<resident_id>`."
  use Oneiroi.Router,
    aggregate: "Oneiroi.Ethos.Character",
    prefix: "ethos-",
    commands: "Oneiroi.Ethos.Commands",
    dispatching:
      ~w(PlantSeed WiltSeed GraduateSeed CiteSeed DefineHabit ChangeHabit AffirmHabit CiteHabit CiteSoulLine TakeBaseline MakeCommitment KeepCommitment ReleaseCommitment)
end
