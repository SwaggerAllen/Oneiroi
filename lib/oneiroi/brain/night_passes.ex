defmodule Oneiroi.Brain.NightPasses do
  @moduledoc """
  The notes for the night passes after the scene pass (sunna#57,
  brain#91; design/portraits.md, the witness's calls of 2026-11-13): the
  people pass and the behaviour pass, each a housekeeping conversation of
  its own, chained after the scenes and before free time. Both read the
  day's scene rows, which she wrote at bedtime, rather than the day again;
  both act as her (they plant and cite, never propose); seed_plant is
  theirs alone.

  A day gives a pass nothing when its rows name no one (people) or there
  are no scenes at all (behaviour), and the pass is skipped: the chain
  goes on to what follows.
  """

  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Seshat

  @doc "The note for turn `n` of `pass` on `day`, or `:skip` when the day gives it nothing."
  @spec note(String.t(), String.t(), String.t(), pos_integer()) :: {:ok, String.t()} | :skip
  def note(_resident_id, pass, day, n) when n > 1,
    do: {:ok, Prompt.render!("night_pass_continue", %{pass: label(pass), day: day, turn: n})}

  def note(resident_id, "people", day, _n) do
    rows = scenes(resident_id, day)

    case people(rows) do
      [] ->
        :skip

      names ->
        {:ok,
         Prompt.render!("people_pass", %{
           day: day,
           people: Enum.map_join(names, "\n", &person_line(&1, rows)),
           days: Config.fetch!(:ethos, :portrait_days),
           turns: Config.fetch!(:sunna, :people_turns)
         })}
    end
  end

  def note(resident_id, "behaviour", day, _n) do
    case scenes(resident_id, day) do
      [] ->
        :skip

      rows ->
        {:ok,
         Prompt.render!("behaviour_pass", %{
           day: day,
           scenes: Enum.map_join(rows, "\n", &scene_line/1),
           turns: Config.fetch!(:sunna, :behaviour_turns)
         })}
    end
  end

  def note(_resident_id, _pass, _day, _n), do: :skip

  defp label("people"), do: "people pass"
  defp label("behaviour"), do: "behaviour pass"
  defp label(other), do: other

  # The day's scenes as rows, corrections left out: the night passes read
  # what the scene pass wrote, in order.
  defp scenes(resident_id, day) do
    resident_id
    |> Seshat.scenes(day, day)
    |> Enum.flat_map(& &1.scenes)
    |> Enum.filter(&(&1.kind == "scene"))
    |> Enum.sort_by(& &1.number)
  end

  defp people(rows), do: rows |> Enum.flat_map(&(&1.people || [])) |> Enum.uniq()

  defp person_line(name, rows) do
    in_scenes =
      rows
      |> Enum.filter(&(name in (&1.people || [])))
      |> Enum.map_join(
        "; ",
        &"scene #{&1.number} \"#{&1.title}\" (turns #{&1.from_turn} to #{&1.to_turn})"
      )

    "- #{name}: #{in_scenes}"
  end

  defp scene_line(s) do
    people = if s.people in [nil, []], do: "", else: " with #{Enum.join(s.people, ", ")}"

    "- scene #{s.number} \"#{s.title}\"#{people} (turns #{s.from_turn} to #{s.to_turn}): #{s.summary}"
  end
end
