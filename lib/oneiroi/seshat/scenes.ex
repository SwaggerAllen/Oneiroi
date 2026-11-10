defmodule Oneiroi.Seshat.Scenes do
  @moduledoc """
  The day's scenes as rows (seshat#52; the witness's call and Lily's
  view, letter #509, design/ui-server-work.md S2): the bedtime pass
  (sunna#34) writes each scene with `scene_write`, one call a scene, and
  the rows are the record the navigator, the calendar and search read.
  Every write re-renders `scenes/<day>.md` from the rows through the
  library's core write, the journal's pattern (seshat#23), so the file
  stays the readable record in her repository.

  A day reads `complete: false` until a write says `final: true`, so a
  pass that ends short (its rounds spent, its turns used) reads as not
  finished and never as the day ending there.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Scene
  alias Oneiroi.Seshat.SceneCommands, as: Commands
  alias Oneiroi.Seshat.SceneRouter, as: Router
  alias Oneiroi.Seshat.Store
  alias Oneiroi.SimaQian
  alias Oneiroi.Sunna

  @writing ~w(title from_turn to_turn from_time to_time summary mood rounds_ran_out register)

  @doc """
  What one `scene_write` call does, from its arguments (text keys):

    * with `scene` (a number): corrects that scene's facts or mood, the
      fields given; a `summary` is refused (seshat#52);
    * with `corrects` (a number): appends a row correcting that scene's
      summary, citing `from_turn` and `to_turn`;
    * else, with any scene field: writes the day's next scene;
    * and with `final: true`, after any of these or alone, closes the day.

  A correction of either kind carries `note`, why. Returns what was done:
  `%{day, number, done, complete}`, `done` one of `written`, `corrected`,
  `unchanged`, `summary_corrected` or `closed`.
  """
  @spec write(String.t(), map(), Actor.t()) :: {:ok, map()} | {:error, Error.t()}
  def write(resident_id, args, %Actor{} = actor) when is_map(args) do
    day = text(args["day"])
    final? = args["final"] == true
    zone = Local.zone(resident_id)

    result =
      cond do
        not is_nil(args["scene"]) -> correct(resident_id, day, args, zone, actor)
        not is_nil(args["corrects"]) -> correct_summary(resident_id, day, args, actor)
        Enum.any?(@writing, &Map.has_key?(args, &1)) -> add(resident_id, day, args, zone, actor)
        final? -> {:ok, %{day: day, number: nil, done: "closed"}}
        true -> {:error, nothing_to_do()}
      end

    with {:ok, done} <- result,
         :ok <- if(final?, do: close(resident_id, day, actor), else: :ok),
         :ok <- render_day(resident_id, day, actor) do
      {:ok, Map.put(done, :complete, complete?(resident_id, day))}
    end
  end

  defp nothing_to_do,
    do:
      Error.new(:seshat_scene_invalid, :seshat_scenes_write_empty,
        detail:
          "a call writes a scene, corrects one (scene or corrects), or closes the day (final)"
      )

  defp add(resident_id, day, args, zone, actor) do
    with {:ok, from_time} <- time(args["from_time"], day, zone),
         {:ok, to_time} <- time(args["to_time"], day, zone),
         {:ok, [event]} <-
           dispatch(%Commands.WriteScene{
             actor: actor,
             at: Clock.now(),
             id: resident_id,
             day: day,
             title: text(args["title"]),
             from_turn: text(args["from_turn"]),
             to_turn: text(args["to_turn"]),
             from_time: from_time,
             to_time: to_time,
             summary: text(args["summary"]),
             mood: blank_to_nil(args["mood"]),
             rounds_ran_out: flag(args["rounds_ran_out"]),
             register: blank_to_nil(args["register"]),
             today: today(resident_id)
           }) do
      {:ok, %{day: day, number: event.number, done: "written"}}
    end
  end

  defp correct(resident_id, day, args, zone, actor) do
    with {:ok, number} <- number(args["scene"]),
         {:ok, note} <- note(args["note"]),
         {:ok, changes} <- changes(args, day, zone),
         {:ok, events} <-
           dispatch(%Commands.CorrectScene{
             actor: actor,
             at: Clock.now(),
             note: note,
             id: resident_id,
             day: day,
             number: number,
             changes: changes,
             today: today(resident_id)
           }) do
      {:ok,
       %{
         day: day,
         number: number,
         done: if(events == [], do: "unchanged", else: "corrected"),
         mood_correction: Enum.any?(events, &(&1.mood_correction == true))
       }}
    end
  end

  defp correct_summary(resident_id, day, args, actor) do
    with {:ok, corrects} <- number(args["corrects"]),
         {:ok, note} <- note(args["note"]),
         {:ok, [event]} <-
           dispatch(%Commands.CorrectSceneSummary{
             actor: actor,
             at: Clock.now(),
             note: note,
             id: resident_id,
             day: day,
             corrects: corrects,
             from_turn: text(args["from_turn"]),
             to_turn: text(args["to_turn"]),
             summary: text(args["summary"])
           }) do
      {:ok, %{day: day, number: event.number, done: "summary_corrected", corrects: corrects}}
    end
  end

  defp close(resident_id, day, actor) do
    command = %Commands.CloseScenes{actor: actor, at: Clock.now(), id: resident_id, day: day}
    with {:ok, _events} <- dispatch(command), do: :ok
  end

  # The fields a correction names, as the history keeps them: text
  # trimmed, times as ISO instants to the second, the flag a boolean.
  defp changes(args, day, zone) do
    fields = Enum.filter(["summary", "mood" | Scene.facts()], &Map.has_key?(args, &1))

    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case change(field, args[field], day, zone) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp change(time, value, day, zone) when time in ["from_time", "to_time"] do
    with {:ok, at} <- time(value, day, zone), do: {:ok, Scene.iso(at)}
  end

  defp change("rounds_ran_out", value, _day, _zone), do: {:ok, flag(value)}

  defp change(field, value, _day, _zone) when field in ["mood", "register"],
    do: {:ok, blank_to_nil(value)}

  defp change(_field, value, _day, _zone), do: {:ok, text(value)}

  defp number(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp number(text) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} when n > 0 -> {:ok, n}
      _other -> number(nil)
    end
  end

  defp number(_other),
    do:
      {:error,
       Error.new(:seshat_scene_invalid, :seshat_scenes_number_invalid,
         detail: "a scene is named by its number within the day"
       )}

  defp note(note) do
    case blank_to_nil(note) do
      nil ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scenes_note_missing,
           detail: "a correction says why, in a note"
         )}

      text ->
        {:ok, text}
    end
  end

  @doc """
  A scene's time as an instant: an ISO instant as given, or `HH:MM` on
  the scene's day in her zone; nil for none.
  """
  @spec time(term(), String.t() | nil, String.t()) ::
          {:ok, DateTime.t() | nil} | {:error, Error.t()}
  def time(nil, _day, _zone), do: {:ok, nil}

  def time(value, day, zone) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:ok, nil}

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, at, _offset} = DateTime.from_iso8601(value)
        {:ok, at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)}

      at = local(value, day, zone) ->
        {:ok, at}

      true ->
        time(:invalid, day, zone)
    end
  end

  def time(_other, _day, _zone),
    do:
      {:error,
       Error.new(:seshat_scene_invalid, :seshat_scenes_time_invalid,
         detail: "a time is HH:MM on the scene's day, or an ISO instant"
       )}

  defp local(value, day, zone) do
    with [h, m] <- String.split(value, ":"),
         {hour, ""} <- Integer.parse(h),
         {minute, ""} <- Integer.parse(m),
         {:ok, clock} <- Time.new(hour, minute, 0),
         true <- is_binary(day),
         {:ok, date} <- Date.from_iso8601(day) do
      at =
        case DateTime.new(date, clock, zone) do
          {:ok, at} -> at
          {:ambiguous, first, _second} -> first
          {:gap, _before, after_gap} -> after_gap
        end

      DateTime.shift_zone!(at, "Etc/UTC")
    else
      _not_local -> nil
    end
  end

  # ---- reads ----

  @doc """
  The days with scenes in `[from, to]` (ISO dates, either nil for open),
  oldest first, each `%{day, complete, closed_at, scenes}` with every
  row of the day in order: scenes and the corrections of their summaries.
  """
  @spec days(String.t(), String.t() | nil, String.t() | nil) :: [map()]
  def days(resident_id, from, to) do
    Scope.resident(resident_id, fn ->
      rows = Enum.group_by(Store.scenes_between(from, to), & &1.day)

      for d <- Store.scene_days(from, to) do
        %{
          day: d.day,
          complete: d.complete,
          closed_at: d.closed_at,
          scenes: Map.get(rows, d.day, [])
        }
      end
    end)
  end

  @doc "How many scenes each day in `[from, to]` holds, corrections not counted."
  @spec counts(String.t(), String.t(), String.t()) :: %{String.t() => non_neg_integer()}
  def counts(resident_id, from, to),
    do: Map.new(Scope.resident(resident_id, fn -> Store.scene_counts(from, to) end))

  defp complete?(resident_id, day) do
    case Scope.resident(resident_id, fn -> Store.scene_day(day) end) do
      %{complete: complete} -> complete
      nil -> false
    end
  end

  # ---- the file ----

  @registers %{"his" => "his words", "hers" => "her words", "work" => "work"}

  @doc """
  A day's scenes as the file reads them: a heading a scene with its span,
  turns, register and mood, its lines, then any correction of its lines;
  a day not closed says so at the top.
  """
  @spec render(String.t(), [map()], boolean(), String.t()) :: String.t()
  def render(day, rows, complete, zone) do
    {scenes, corrections} = Enum.split_with(rows, &(&1.kind == "scene"))
    corrections = Enum.group_by(corrections, & &1.corrects)

    head =
      if complete,
        do: "# Scenes of #{day}\n",
        else:
          "# Scenes of #{day}\n\n_Not finished: the scene pass has not closed this day, so it may hold more than these scenes._\n"

    body =
      Enum.map_join(scenes, "", fn s ->
        "\n" <>
          scene_text(s, zone) <>
          Enum.map_join(Map.get(corrections, s.number, []), "", &correction_text/1)
      end)

    head <> body
  end

  defp scene_text(s, zone) do
    facts =
      [
        span(s.from_time, s.to_time, zone),
        "turns `#{s.from_turn}` to `#{s.to_turn}`",
        s.register && @registers[s.register],
        s.mood && mood_text(s)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    rounds =
      if s.rounds_ran_out, do: "\n_The tool rounds ran out on this scene._\n", else: ""

    corrected =
      if s.corrected_at,
        do:
          "\n_Facts corrected #{Calendar.strftime(s.corrected_at, "%Y-%m-%d")}; the history keeps what they were._\n",
        else: ""

    "## #{s.number}. #{s.title}\n\n#{facts}\n#{rounds}#{corrected}\n#{s.summary}\n"
  end

  defp mood_text(%{mood_corrected_at: nil} = s), do: "mood: #{s.mood}"

  defp mood_text(s) do
    first = if s.mood_was, do: "; first written: #{s.mood_was}", else: ""

    "mood: #{s.mood} (a correction, #{Calendar.strftime(s.mood_corrected_at, "%Y-%m-%d")}#{first})"
  end

  defp correction_text(c),
    do:
      "\n### Correction to scene #{c.corrects} (row #{c.number}, turns `#{c.from_turn}` to `#{c.to_turn}`)\n\n#{c.summary}\n"

  defp span(nil, nil, _zone), do: nil
  defp span(from, nil, zone), do: "from #{clock(from, zone)}"
  defp span(nil, to, zone), do: "until #{clock(to, zone)}"
  defp span(from, to, zone), do: "#{clock(from, zone)}–#{clock(to, zone)}"

  defp clock(at, zone), do: at |> DateTime.shift_zone!(zone) |> Calendar.strftime("%H:%M")

  defp render_day(resident_id, day, actor) do
    zone = Local.zone(resident_id)

    {rows, complete} =
      Scope.resident(resident_id, fn ->
        {Store.scenes(day), match?(%{complete: true}, Store.scene_day(day))}
      end)

    if rows == [] and not complete do
      :ok
    else
      case Documents.write(resident_id, path(day), render(day, rows, complete, zone), actor,
             core: true
           ) do
        {:ok, _} -> :ok
        other -> other
      end
    end
  end

  @doc "Where a day's scenes are read: `scenes/<day>.md`."
  @spec path(String.t()) :: String.t()
  def path(day), do: "scenes/#{day}.md"

  # ---- the backfill (seshat#52) ----

  @doc """
  Reads the days written as prose before the rows into rows, best-effort:
  each `scenes/<day>.md` in her repository whose day has no rows yet is
  parsed (`parse/3`); a day that parses cleanly becomes its scenes,
  closed, and its file is rendered from them; a day that does not stays
  as prose, untouched, with no rows. With `dry_run: true` nothing is
  written. Returns `%{rows: [{day, count}], prose: [{day, why}], skipped: [day]}`.
  """
  @spec backfill(String.t(), Actor.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def backfill(resident_id, %Actor{} = actor, opts \\ []) do
    zone = Local.zone(resident_id)

    with {:ok, dir} <- SimaQian.repository_dir(resident_id) do
      had = resident_id |> days(nil, nil) |> MapSet.new(& &1.day)

      result =
        dir
        |> files()
        |> Enum.reduce(%{rows: [], prose: [], skipped: []}, fn {day, file}, acc ->
          backfill_day(resident_id, day, file, zone, had, actor, opts, acc)
        end)

      {:ok, Map.new(result, fn {k, v} -> {k, Enum.reverse(v)} end)}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp backfill_day(resident_id, day, file, zone, had, actor, opts, acc) do
    with false <- MapSet.member?(had, day),
         {:ok, scenes} <- parse(day, File.read!(file), zone) do
      if opts[:dry_run] != true, do: :ok = write_parsed(resident_id, day, scenes, actor)
      %{acc | rows: [{day, length(scenes)} | acc.rows]}
    else
      true -> %{acc | skipped: [day | acc.skipped]}
      {:prose, why} -> %{acc | prose: [{day, why} | acc.prose]}
    end
  end

  defp write_parsed(resident_id, day, scenes, actor) do
    Enum.each(scenes, fn scene ->
      {:ok, _} =
        dispatch(%Commands.WriteScene{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          day: day,
          title: scene.title,
          from_turn: scene.from_turn,
          to_turn: scene.to_turn,
          from_time: scene.from_time,
          to_time: scene.to_time,
          summary: scene.summary,
          mood: scene.mood,
          rounds_ran_out: false,
          register: nil,
          today: today(resident_id)
        })
    end)

    with :ok <- close(resident_id, day, actor), do: render_day(resident_id, day, actor)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp files(dir) do
    folder = Path.join(dir, "scenes")

    case File.ls(folder) do
      {:ok, names} ->
        for name <- Enum.sort(names),
            [_, day] <- [Regex.run(~r/\A(\d{4}-\d{2}-\d{2})\.md\z/, name)],
            match?({:ok, _}, Date.from_iso8601(day)),
            do: {day, Path.join(folder, name)}

      {:error, _absent} ->
        []
    end
  end

  @ref ~r/[\[`]([A-Za-z0-9_-]{16})[\]`]/
  @clock ~r/(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])/
  @heading ~r/\A\#{2,3}\s+(.*\S)\s*\z/
  @mood ~r/\A[\W_]*mood[\W_]*:\s*(.+?)[\W_]*\z/iu

  @doc """
  A prose day's scenes, best-effort (seshat#52): one `##` or `###`
  heading a scene, nothing but a `#` title before the first; each scene
  cites at least one turn ref in brackets or backticks (its first and
  last are the span's), its first and last `HH:MM` are its times on the
  day, a `mood:` line is its mood, and the lines left are its summary.
  Anything else is `{:prose, why}`, and the day stays prose.
  """
  @spec parse(String.t(), String.t(), String.t()) :: {:ok, [map()]} | {:prose, String.t()}
  def parse(day, text, zone) do
    {preamble, sections} = text |> String.split("\n") |> Enum.reduce({[], []}, &by_heading/2)

    cond do
      Enum.any?(preamble, &(String.trim(&1) != "" and not String.starts_with?(&1, "# "))) ->
        {:prose, "prose before the first scene's heading"}

      sections == [] ->
        {:prose, "no scene headings"}

      true ->
        sections |> Enum.reverse() |> Enum.with_index(1) |> sections(day, zone, [])
    end
  end

  defp by_heading(line, {pre, secs}) do
    case {Regex.run(@heading, line), secs} do
      {[_, heading], _} -> {pre, [{heading, []} | secs]}
      {nil, []} -> {[line | pre], secs}
      {nil, [{heading, body} | rest]} -> {pre, [{heading, [line | body]} | rest]}
    end
  end

  defp sections([], _day, _zone, acc), do: {:ok, Enum.reverse(acc)}

  defp sections([{{heading, body}, n} | rest], day, zone, acc) do
    case section(day, heading, Enum.reverse(body), zone) do
      {:ok, scene} -> sections(rest, day, zone, [scene | acc])
      {:prose, why} -> {:prose, "scene #{n}: #{why}"}
    end
  end

  defp section(day, heading, body, zone) do
    whole = Enum.join([heading | body], "\n")
    refs = for [_, ref] <- Regex.scan(@ref, whole), do: ref
    times = for [_, h, m] <- Regex.scan(@clock, whole), do: "#{h}:#{m}"
    title = heading |> strip() |> String.trim()

    summary =
      body
      |> Enum.reject(&(mood_line(&1) || metadata?(&1)))
      |> Enum.join("\n")
      |> String.trim()

    with :ok <- present(refs, "cites no turn"),
         :ok <- present(title, "no title"),
         :ok <- present(summary, "no lines"),
         {:ok, from, to} <- span_times(times, day, zone) do
      {:ok,
       %{
         title: String.slice(title, 0, 200),
         from_turn: List.first(refs),
         to_turn: List.last(refs),
         from_time: from,
         to_time: to,
         summary: summary,
         mood: Enum.find_value(body, &mood_line/1)
       }}
    end
  end

  defp present(empty, why) when empty in [[], ""], do: {:prose, why}
  defp present(_value, _why), do: :ok

  # The first and the last time named; a last before the first (a scene
  # past midnight) is left open rather than guessed.
  defp span_times(times, day, zone) do
    with {:ok, from} <- parsed_time(List.first(times), day, zone),
         {:ok, to} <- parsed_time(if(length(times) > 1, do: List.last(times)), day, zone) do
      if from && to && DateTime.compare(from, to) == :gt,
        do: {:ok, from, nil},
        else: {:ok, from, to}
    end
  end

  defp parsed_time(value, day, zone) do
    case time(value, day, zone) do
      {:ok, at} -> {:ok, at}
      {:error, _} -> {:prose, "a time that is no time"}
    end
  end

  defp mood_line(line) do
    case Regex.run(@mood, String.trim(line)) do
      [_, mood] -> if String.length(mood) <= 200, do: String.trim(mood)
      nil -> nil
    end
  end

  # A line of the span and the turns alone: nothing left once its refs,
  # times and the words that name them are taken out.
  defp metadata?(line) do
    String.trim(line) != "" and
      line
      |> strip()
      |> String.replace(~r/\b(turns?|refs?|time|span|from|to|through|until|and)\b/i, "")
      |> String.match?(~r/\A[\W_]*\z/u)
  end

  defp strip(text) do
    text
    |> String.replace(@ref, "")
    |> String.replace(@clock, "")
    |> String.replace(~r/\A\s*(scene\s+)?\d+[.:)]?\s+/i, "")
    |> String.replace(~r/\A[\s\p{Pd}·:|,()\[\]*_]+|[\s\p{Pd}·:|,()\[\]*_]+\z/u, "")
  end

  # ---- helpers ----

  defp today(resident_id), do: Sunna.today(resident_id).day

  defp text(nil), do: nil
  defp text(value) when is_binary(value), do: String.trim(value)
  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(_other), do: nil

  defp flag(true), do: true
  defp flag("true"), do: true
  defp flag(_other), do: false

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case text(value) do
      "" -> nil
      other -> other
    end
  end

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:seshat_dispatch_failed, :seshat_scenes_dispatch_failed, reason)}
    end
  end
end
