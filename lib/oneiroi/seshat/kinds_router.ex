defmodule Oneiroi.Seshat.KindsRouter do
  @moduledoc "The kinds aggregate's router (seshat#51): `kinds-<resident_id>`, her own kinds and the system kinds' gates."
  # Names rather than aliases: see `Oneiroi.Router`.
  use Oneiroi.Router,
    aggregate: "Oneiroi.Seshat.KindsLedger",
    prefix: "kinds-",
    commands: "Oneiroi.Seshat.Commands",
    dispatching: ~w(DefineKind ProposeKindGate AnswerKindGate)
end
