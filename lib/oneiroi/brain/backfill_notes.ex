defmodule Oneiroi.Brain.BackfillNotes do
  @moduledoc """
  The memory backfill's notes (sunna#59, brain#96): what Lily is asked to
  do for one past day, pass by pass, in housekeeping conversations of her
  own. The brain writes them because they read the scene rows (the
  library's) and the transcripts' shape (memory's), which the schedule
  does not.

  - **scenes**: the day's Oneiroi chat, where to read it, grouped into
    scenes with `scene_write` for that day; skipped when the day is
    already closed or the chat said nothing that day.
  - **domains**: every conversation of the day (the chat by its scenes,
    every other by its turns) named into domains with `domain_tag`, from
    his list and hers; skipped when nothing was said that day.
  - **people**: the night's people pass for that day, citing each
    moment by its turn or journal row, so a portrait's days are the days
    the moments happened (ethos#23); it reads that day's journal rows
    whole as the nightly pass does (ethos#24), and is skipped only when
    the scenes name no one and the day has no journal rows.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Brain.NightPasses
  alias Oneiroi.Config
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Seshat

  # Her own runs that are machinery, not conversation: never tagged.
  @untagged ~w(housekeeping)
  @actor Actor.new(:job, "sunna_backfill")

  @doc "The note for turn `n` of a backfill `pass` on `day`, or `:skip`."
  @spec note(String.t(), String.t(), String.t(), pos_integer(), map()) ::
          {:ok, String.t()} | :skip
  def note(_resident_id, pass, day, n, _lists) when n > 1,
    do:
      {:ok,
       Prompt.render!("night_pass_continue", %{pass: "backfill #{pass} pass", day: day, turn: n})}

  def note(resident_id, "scenes", day, _n, _lists) do
    with false <- closed?(resident_id, day),
         %{} = chat <- chat(sessions(resident_id, day)) do
      {:ok,
       Prompt.render!("backfill_scenes", %{
         day: day,
         session: chat.key,
         from: chat.from,
         count: chat.messages,
         turns: Config.fetch!(:sunna, :backfill_scene_turns)
       })}
    else
      _closed_or_quiet -> :skip
    end
  end

  def note(resident_id, "domains", day, n, lists) do
    case Enum.reject(sessions(resident_id, day), &(&1.kind in @untagged)) do
      [] ->
        :skip

      rows ->
        scenes = scenes(resident_id, day)
        {from, to} = bounds(resident_id, day)

        # Only declared domains (kumbukumbu#100): before the day's first
        # turn, its tags of undeclared domains go back to the common room,
        # so none carries past what she names now.
        if n == 1, do: {:ok, _} = Kumbukumbu.clear_undeclared(resident_id, from, to, @actor)

        {:ok,
         Prompt.render!("backfill_domains", %{
           day: day,
           his: words(lists["his"]),
           hers: words(lists["hers"]),
           conversations: Enum.map_join(rows, "\n", &conversation_line(&1, scenes)),
           named: named_words(Kumbukumbu.day_tag_points(resident_id, from, to)),
           turns: Config.fetch!(:sunna, :backfill_domain_turns)
         })}
    end
  end

  def note(resident_id, "people", day, _n, _lists) do
    rows = scenes(resident_id, day)

    case {NightPasses.people(rows), NightPasses.journal(resident_id, day)} do
      {[], []} ->
        :skip

      {names, entries} ->
        {:ok,
         Prompt.render!("backfill_people", %{
           day: day,
           people: NightPasses.people_lines(names, rows),
           journal: NightPasses.journal_lines(entries, day),
           days: Config.fetch!(:ethos, :portrait_days),
           turns: Config.fetch!(:sunna, :people_turns)
         })}
    end
  end

  def note(_resident_id, _pass, _day, _n, _lists), do: :skip

  defp named_words([]), do: "none yet."

  defp named_words(points),
    do:
      Enum.map_join(points, "; ", fn p ->
        "#{p.session_key} turn #{p.turn_ref}: #{p.domain || "the common room"}"
      end) <> "."

  # The day's chat with him: the Oneiroi chat, or before it existed the
  # chat an import carried (10-17 to 10-31 are imported), the largest
  # when there are several.
  defp chat(sessions) do
    Enum.find(sessions, &(&1.kind == "main")) ||
      sessions
      |> Enum.filter(&(&1.kind == "imported"))
      |> Enum.max_by(& &1.messages, fn -> nil end)
  end

  # The day's conversations in her zone: each with its kind, what it is
  # called, how many messages, its first and last turn and where a read of
  # the day starts.
  defp sessions(resident_id, day) do
    {from, to} = bounds(resident_id, day)
    Kumbukumbu.day_sessions(resident_id, from, to)
  end

  @doc "A day's bounds in her zone, as UTC instants: `{from, to}`."
  def bounds(resident_id, day) do
    zone = Local.zone(resident_id)
    date = Date.from_iso8601!(day)
    {start(date, zone), start(Date.add(date, 1), zone)}
  end

  defp start(date, zone) do
    local =
      case DateTime.new(date, ~T[00:00:00], zone) do
        {:ok, at} -> at
        {:ambiguous, first, _second} -> first
        {:gap, _before, after_gap} -> after_gap
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end

  defp closed?(resident_id, day) do
    case Seshat.scenes(resident_id, day, day) do
      [%{complete: true} | _] -> true
      _open -> false
    end
  end

  defp scenes(resident_id, day) do
    resident_id
    |> Seshat.scenes(day, day)
    |> Enum.flat_map(& &1.scenes)
    |> Enum.filter(&(&1.kind == "scene"))
    |> Enum.sort_by(& &1.number)
  end

  defp conversation_line(%{kind: kind} = c, scenes) when kind in ["main", "imported"] do
    head =
      "- #{if kind == "main", do: "the Oneiroi chat", else: "the chat as imported"}, session #{c.key}: #{c.messages} messages that day, from #{c.from} (turns #{c.first_turn} to #{c.last_turn})"

    case scenes do
      [] ->
        head <> "; no scenes for the day, so name it by its turns."

      rows ->
        head <>
          ", in scenes:\n" <>
          Enum.map_join(rows, "\n", fn s ->
            "  - scene #{s.number} \"#{s.title}\" (turns #{s.from_turn} to #{s.to_turn})"
          end)
    end
  end

  defp conversation_line(c, _scenes) do
    called = if c.label, do: " (#{c.label})", else: ""

    "- #{kind_words(c.kind)}#{called}, session #{c.key}: #{c.messages} messages that day, from #{c.from} (turns #{c.first_turn} to #{c.last_turn})"
  end

  defp kind_words("free_time"), do: "free time"
  defp kind_words("adapter"), do: "a Claude Code conversation"
  defp kind_words("work"), do: "a work run"
  defp kind_words("round"), do: "a round"
  defp kind_words(kind), do: kind

  defp words([]), do: "none named yet; name them as you go"
  defp words(nil), do: "none named yet; name them as you go"
  defp words(list), do: Enum.join(list, ", ")
end
