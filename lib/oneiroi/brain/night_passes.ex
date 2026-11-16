defmodule Oneiroi.Brain.NightPasses do
  @moduledoc """
  The notes for the night passes after the scene pass (sunna#57,
  brain#91; design/portraits.md, the witness's calls of 2026-11-13): the
  people pass and the behaviour pass, each a housekeeping conversation of
  its own, chained after the scenes and before free time. Both read the
  day's scene rows, which she wrote at bedtime, rather than the day again;
  both act as her (they plant and cite, never propose); seed_plant is
  theirs alone.

  The people pass also reads the day's journal rows whole (ethos#24,
  portraits v2): they carry no people column, so it finds the names in
  them itself and cites a row as `<day>/<n>`.

  A day gives a pass nothing when its scenes name no one and it has no
  journal rows (people) or there are no scenes at all (behaviour), and
  the pass is skipped: the chain goes on to what follows.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Seshat
  alias Oneiroi.Xenia

  @doc "The note for turn `n` of `pass` on `day`, or `:skip` when the day gives it nothing."
  @spec note(String.t(), String.t(), String.t(), pos_integer()) :: {:ok, String.t()} | :skip
  def note(_resident_id, pass, day, n) when n > 1,
    do: {:ok, Prompt.render!("night_pass_continue", %{pass: label(pass), day: day, turn: n})}

  def note(resident_id, "people", day, _n) do
    rows = scenes(resident_id, day)

    case {people(rows), journal(resident_id, day)} do
      {[], []} ->
        :skip

      {names, entries} ->
        {:ok,
         Prompt.render!("people_pass", %{
           day: day,
           people: people_lines(names, rows),
           journal: journal_lines(entries, day),
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

  # The day's presence pass (xenia#20): drawn here, once a day, and
  # skipped while presence is off or the sample held nothing to read.
  def note(resident_id, "presence", day, _n) do
    case Xenia.draw_presence(resident_id, day, Actor.new(:job, "xenia_presence")) do
      {:ok, %{pass: pass, reads: [_ | _] = reads}} ->
        waiting =
          for %{interaction: i, read: r} <- Xenia.presence_interactions(resident_id, ["revise"]),
              do: "- ##{i.number} #{i.kind} on #{(r && r.title) || i.item}: he asks: #{i.comment}"

        {:ok,
         Prompt.render!("presence_pass", %{
           day: day,
           pass: pass.number,
           cap: pass.cap,
           items: Enum.map_join(reads, "\n", &presence_line/1),
           revisions: if(waiting == [], do: "(none)", else: Enum.join(waiting, "\n")),
           turns: Config.fetch!(:sunna, :presence_turns)
         })}

      _off_or_empty ->
        :skip
    end
  end

  def note(_resident_id, _pass, _day, _n), do: :skip

  defp presence_line(r) do
    what = if r.title, do: "\"#{r.title}\"", else: "a note"

    "- #{r.item} (#{r.cut}): #{what} from #{r.account}, #{r.likes} likes, #{r.comments} comments, #{r.restacks} restacks — #{r.excerpt}"
  end

  defp label("people"), do: "people pass"
  defp label("presence"), do: "presence pass"
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

  @doc "The day's journal rows, in order (ethos#24): none when the day was never opened."
  @spec journal(String.t(), String.t()) :: [map()]
  def journal(resident_id, day) do
    case Seshat.journal_day(resident_id, day) do
      %{entries: entries} -> Enum.sort_by(entries, & &1.number)
      nil -> []
    end
  end

  @doc "Journal rows as the people passes read them, each with its `<day>/<n>` ref."
  @spec journal_lines([map()], String.t()) :: String.t()
  def journal_lines([], _day), do: "(no journal rows that day)"

  def journal_lines(entries, day),
    do: Enum.map_join(entries, "\n", &"- #{day}/#{&1.number} (#{&1.kind}): #{&1.text}")

  @doc "The scenes' people as the people passes read them, each with the scenes and turns it is in."
  @spec people_lines([String.t()], [map()]) :: String.t()
  def people_lines([], _rows), do: "(no scene named anyone that day)"
  def people_lines(names, rows), do: Enum.map_join(names, "\n", &person_line(&1, rows))

  @doc "The people the day's scene rows name, once each."
  @spec people([map()]) :: [String.t()]
  def people(rows), do: rows |> Enum.flat_map(&(&1.people || [])) |> Enum.uniq()

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
