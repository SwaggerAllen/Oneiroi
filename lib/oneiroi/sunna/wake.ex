defmodule Oneiroi.Sunna.Wake do
  @moduledoc """
  The wake port (spec §6.7, §8): what the schedule calls when a check-in
  fires or free time opens, with the core's note and the purpose the
  answer is billed under. The in-core brain answers it; a brain adapter
  wired by remote trigger will answer it the same way.

  A port rather than a call, because the brain reads this system's dates
  on every turn (the countdowns, spec §6.7) and the schedule wakes the
  brain: a direct call each way is a cycle Boundary and `mix xref graph
  --format cycles` both reject. The implementation is named in
  `SUNNA_WAKE`, the same shape as the ledger's provider port, and is read
  at the call, so neither compiler sees an edge.
  """

  @doc "Wakes the resident in the session with the note; the answer is a captured turn."
  @callback wake(
              resident_id :: String.t(),
              session_key :: String.t(),
              note :: String.t(),
              purpose :: atom()
            ) :: {:ok, map()} | {:error, term()}
end
