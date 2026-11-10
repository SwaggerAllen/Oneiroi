# The scenes' events (seshat#52), under the library's `Events` namespace
# so the events census (`events/0` against the compiled modules) sees
# them; the file is theirs alone.

defmodule Oneiroi.Seshat.Events.SceneWritten do
  @moduledoc """
  A scene of a day (seshat#52) on `scenes-<resident_id>`: its number
  within the day, a title, the turns it covers (`from_turn`, `to_turn`,
  turn refs) and its span (`from_time`, `to_time`, either nil), her few
  lines (`summary`), a mood line of hers or nil, whether the pass's tool
  rounds ran out on it, and its register (`his`, `hers` or `work`, or
  nil). `written_on` is the resident's local day when it was written,
  which the mood's same-day rule reads.
  """
  # Version 2 adds `people` (seshat#57): the persons in the scene, by the
  # names she uses, trimmed and de-duplicated, at most `Scene.people_max/0`
  # of them; the upcaster reads a version 1 scene as naming no one, `[]`.
  use Oneiroi.Event,
    version: 2,
    fields: [
      :id,
      :day,
      :number,
      :title,
      :from_turn,
      :to_turn,
      :from_time,
      :to_time,
      :summary,
      :mood,
      :rounds_ran_out,
      :register,
      :people,
      :written_on
    ],
    instants: [:from_time, :to_time]
end

defimpl Commanded.Event.Upcaster, for: Oneiroi.Seshat.Events.SceneWritten do
  def upcast(%{people: nil} = event, _metadata), do: %{event | people: []}
  def upcast(event, _metadata), do: event
end

defmodule Oneiroi.Seshat.Events.SceneCorrected do
  @moduledoc """
  A scene's facts or mood corrected (seshat#52), a decision with its
  note. `changes` is the new values and `was` the old, both keyed by
  field name with instants as ISO text, so the history keeps every value
  a scene ever had. `mood_correction` is true when the mood moved after
  the local day it was written, which the row and the file then mark
  as a correction. `people` is a fact like the title (seshat#57): a
  correction may move it, the list it replaced kept in `was`; the shape
  is the same map, so the version stays 1.
  """
  use Oneiroi.Event,
    version: 1,
    decision: true,
    fields: [:id, :day, :number, :changes, :was, :mood_correction, :written_on]
end

defmodule Oneiroi.Seshat.Events.SceneSummaryCorrected do
  @moduledoc """
  A scene's summary corrected by a row of its own (seshat#52), a
  decision with its note: `number` the new row's, `corrects` the scene's,
  the turns it cites and the corrected lines. The scene's own summary is
  never overwritten.
  """
  use Oneiroi.Event,
    version: 1,
    decision: true,
    fields: [:id, :day, :number, :corrects, :from_turn, :to_turn, :summary]
end

defmodule Oneiroi.Seshat.Events.ScenesClosed do
  @moduledoc """
  A day's scenes closed (seshat#52): the pass read the whole day and
  wrote its last scene. Until this, the day reads as not finished.
  `count` is how many scenes it held when closed.
  """
  use Oneiroi.Event, version: 1, fields: [:id, :day, :count]
end
