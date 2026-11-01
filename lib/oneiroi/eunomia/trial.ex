defmodule Oneiroi.Eunomia.Trial do
  @moduledoc """
  The trial port (spec §6.4, eunomia #10): what a regression run calls to
  have one candidate model answer one trial. The answer is a normal turn
  in a fresh session, with the resident's memory retrieved and its whole
  tool surface, every tool that would change anything answering as it
  does on success and recording nothing; the resident is told nothing of
  the run.

  A port rather than a call, because the brain depends on this system
  (the judgement tools, the trial tools, the movement section) and a turn
  is the brain's: a direct call back is the cycle Boundary and `mix xref
  graph --format cycles` both reject. The implementation is named in
  `EUNOMIA_TRIAL` and read at the call, the schedule's wake port's shape
  (sunna #12), so neither compiler sees an edge.
  """

  alias Oneiroi.Nisaba.Provider.Result

  @doc """
  Answers `prompt` as `model` in a fresh session of the resident's, every
  model call and retrieval billed under `regression` to `actor`. The
  result is the turn's last reply, refusal included; a provider failure
  comes back as that failure, sited, for the card to carry.
  """
  @callback trial(
              resident_id :: String.t(),
              model :: String.t(),
              prompt :: String.t(),
              actor :: Oneiroi.Actor.t()
            ) :: {:ok, Result.t()} | {:error, term()}
end
