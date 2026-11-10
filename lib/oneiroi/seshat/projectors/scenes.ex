defmodule Oneiroi.Seshat.Projectors.Scenes do
  @moduledoc "Folds the scenes streams (seshat#52) into scene rows and day rows."
  use Oneiroi.Projection, name: "seshat_scenes"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.Store.Scene
  alias Oneiroi.Seshat.Store.SceneDay

  fold(%Events.SceneWritten{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :scene,
      %Scene{
        resident_id: e.id,
        day: e.day,
        number: e.number,
        kind: "scene",
        title: e.title,
        from_turn: e.from_turn,
        to_turn: e.to_turn,
        from_time: usec(e.from_time),
        to_time: usec(e.to_time),
        summary: e.summary,
        mood: e.mood,
        rounds_ran_out: e.rounds_ran_out == true,
        register: e.register,
        at: e.at,
        actor_kind: actor_kind(e.actor)
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :day, :number]
    )
    |> open_day(e)
  end)

  fold(%Events.SceneSummaryCorrected{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :scene,
      %Scene{
        resident_id: e.id,
        day: e.day,
        number: e.number,
        kind: "correction",
        corrects: e.corrects,
        from_turn: e.from_turn,
        to_turn: e.to_turn,
        summary: e.summary,
        at: e.at,
        actor_kind: actor_kind(e.actor)
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :day, :number]
    )
    |> open_day(e)
  end)

  fold(%Events.SceneCorrected{} = e, _metadata, fn multi ->
    Multi.run(multi, :corrected, fn repo, _done ->
      case repo.one(
             from(s in Scene,
               where: s.resident_id == ^e.id and s.day == ^e.day and s.number == ^e.number
             )
           ) do
        nil ->
          {:ok, nil}

        row ->
          row |> Ecto.Changeset.change(fields(row, e)) |> repo.update()
      end
    end)
  end)

  fold(%Events.ScenesClosed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :closed,
      %SceneDay{resident_id: e.id, day: e.day, complete: true, closed_at: e.at},
      on_conflict: {:replace, [:complete, :closed_at]},
      conflict_target: [:resident_id, :day]
    )
  end)

  defp open_day(multi, e),
    do:
      Multi.insert(multi, :day, %SceneDay{resident_id: e.id, day: e.day, complete: false},
        on_conflict: :nothing,
        conflict_target: [:resident_id, :day]
      )

  @facts %{
    "title" => :title,
    "from_turn" => :from_turn,
    "to_turn" => :to_turn,
    "register" => :register,
    "rounds_ran_out" => :rounds_ran_out
  }

  # The row's new values: each fact moved, the times read back from the
  # history's text, and the mood with, past its day, the mood it was
  # first written with and when it was corrected.
  defp fields(row, e) do
    changes = Oneiroi.Seshat.Scene.texts(e.changes)
    was = Oneiroi.Seshat.Scene.texts(e.was)

    facts = for {key, field} <- @facts, Map.has_key?(changes, key), do: {field, changes[key]}

    times =
      for key <- ["from_time", "to_time"],
          Map.has_key?(changes, key),
          do: {String.to_existing_atom(key), instant(changes[key])}

    mood =
      cond do
        not Map.has_key?(changes, "mood") ->
          []

        e.mood_correction ->
          [mood: changes["mood"], mood_was: row.mood_was || was["mood"], mood_corrected_at: e.at]

        true ->
          [mood: changes["mood"]]
      end

    Map.new(facts ++ times ++ mood ++ [corrected_at: e.at])
  end

  defp instant(nil), do: nil

  defp instant(text) when is_binary(text) do
    {:ok, at, _offset} = DateTime.from_iso8601(text)
    usec(at)
  end

  defp usec(nil), do: nil

  defp usec(%DateTime{} = at) do
    {us, _precision} = at.microsecond
    %{DateTime.shift_zone!(at, "Etc/UTC") | microsecond: {us, 6}}
  end

  defp actor_kind(%{kind: kind}), do: Atom.to_string(kind)
  defp actor_kind(_other), do: nil
end
