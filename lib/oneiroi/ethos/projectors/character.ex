defmodule Oneiroi.Ethos.Projectors.Character do
  @moduledoc "Folds the character stream into seeds, habits, citations and affirmations."
  use Oneiroi.Projection, name: "ethos_character"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Ethos.Events
  alias Oneiroi.Ethos.Store.{Affirmation, Baseline, Citation, Commitment, Habit, Seed}

  fold(%Events.SeedPlanted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :seed,
      %Seed{resident_id: e.id, number: e.number, text: e.text, state: "open", planted_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.SeedWilted{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:seed, e.number},
      from(s in Seed, where: s.resident_id == ^e.id and s.number == ^e.number),
      set: [state: "wilted", closed_at: e.at]
    )
  end)

  fold(%Events.SeedGraduated{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:seed, e.number},
      from(s in Seed, where: s.resident_id == ^e.id and s.number == ^e.number),
      set: [
        state: "graduated",
        closed_at: e.at,
        graduated_to_kind: e.to_kind,
        graduated_to_id: e.to_id,
        graduation_note: e.note
      ]
    )
  end)

  fold(%Events.SeedCited{} = e, _metadata, fn multi -> cite(multi, "seed", e) end)

  fold(%Events.HabitDefined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :habit,
      %Habit{
        resident_id: e.id,
        number: e.number,
        name: e.name,
        trigger: e.trigger,
        stance: e.stance,
        seed_number: e.seed_number,
        defined_by_kind: actor_field(e.actor, :kind),
        defined_by_id: actor_field(e.actor, :id),
        defined_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.HabitChanged{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      {:habit, e.number},
      from(h in Habit, where: h.resident_id == ^e.id and h.number == ^e.number),
      set: [name: e.name, trigger: e.trigger, stance: e.stance, revised_at: e.at],
      inc: [revisions: 1]
    )
  end)

  fold(%Events.HabitAffirmed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :affirmation,
      %Affirmation{
        resident_id: e.id,
        number: e.number,
        at: e.at,
        note: e.note,
        by_kind: actor_field(e.actor, :kind),
        by_id: actor_field(e.actor, :id)
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.HabitCited{} = e, _metadata, fn multi -> cite(multi, "habit", e) end)
  fold(%Events.SoulLineCited{} = e, _metadata, fn multi -> cite(multi, "soul", e) end)

  fold(%Events.BaselineTaken{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :baseline,
      %Baseline{
        resident_id: e.id,
        at: e.at,
        habits: e.habits,
        spread: e.spread,
        breadth: e.breadth
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :at]
    )
  end)

  fold(%Events.CommitmentMade{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :commitment,
      %Commitment{
        resident_id: e.id,
        number: e.number,
        to: e.to,
        text: e.text,
        made_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.CommitmentKept{} = e, _metadata, fn multi -> close(multi, e, "kept") end)
  fold(%Events.CommitmentReleased{} = e, _metadata, fn multi -> close(multi, e, "released") end)

  defp close(multi, e, state) do
    Multi.update_all(
      multi,
      {:commitment, e.number},
      from(c in Commitment, where: c.resident_id == ^e.id and c.number == ^e.number),
      set: [
        state: state,
        closed_at: e.at,
        closed_by_kind: actor_field(e.actor, :kind),
        note: e.note
      ]
    )
  end

  defp cite(multi, kind, e) do
    Multi.insert(
      multi,
      {:citation, kind, e.number},
      %Citation{
        resident_id: e.id,
        kind: kind,
        number: e.number,
        target_kind: e.target_kind,
        target_id: to_string(e.target_id),
        at: e.at,
        movement: e.movement
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :kind, :number, :target_kind, :target_id]
    )
  end

  defp actor_field(%{} = actor, key) do
    case Map.get(actor, key) || Map.get(actor, Atom.to_string(key)) do
      nil -> nil
      value -> to_string(value)
    end
  end

  defp actor_field(_other, _key), do: nil
end
