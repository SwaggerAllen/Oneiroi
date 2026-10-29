# The journal's events, under the library's `Events` namespace so the
# events census (`events/0` against the compiled modules) sees them;
# the file is theirs alone.

defmodule Oneiroi.Seshat.Events.JournalEntryAdded do
  @moduledoc """
  A journal row (spec §6.5, F29) on `journal-<resident_id>`: a day, the
  entry's number within the day, a kind (plan, note, todo, wrap) and
  its text; the narrative file is rendered from these.
  """
  use Oneiroi.Event, version: 1, fields: [:id, :day, :number, :kind, :text]
end

defmodule Oneiroi.Seshat.Events.JournalTodoDone do
  @moduledoc "A to-do row marked done."
  use Oneiroi.Event, version: 1, fields: [:id, :day, :number]
end
