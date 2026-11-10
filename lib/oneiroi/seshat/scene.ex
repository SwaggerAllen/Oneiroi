defmodule Oneiroi.Seshat.Scene do
  @moduledoc """
  The scenes aggregate on `scenes-<resident_id>` (seshat#52). Pure: per
  day it counts the rows, so a scene's number is its position within the
  day and a rebuild numbers them the same; holds each scene's facts and
  mood with the local day the mood was written; and whether the day is
  closed.

  The edits are asymmetric, as the resident asked (letter #509): facts
  (title, turns, times, register, whether the rounds ran out, the
  people in it, seshat#57) are
  correctable on any day, the old values kept in the event; a summary is
  never overwritten, only corrected by a row of its own citing its turns;
  the mood moves freely on the local day it was written, and after that
  only as a correction marked as one.
  """

  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Events
  alias Oneiroi.Seshat.SceneCommands, as: Commands

  defstruct [:id, days: %{}]

  @registers ~w(his hers work)
  @facts ~w(title from_turn to_turn from_time to_time register rounds_ran_out people)
  @line 200
  @ref 64
  @people_max 20
  @name 80

  @doc "The registers a scene is in: his words, hers, or work."
  def registers, do: @registers

  @doc "The fields a correction may move besides the mood; the summary is never one."
  def facts, do: @facts

  @doc "The most people a scene names (seshat#57)."
  def people_max, do: @people_max

  @doc "The longest name a scene's people list holds, in characters."
  def name_max, do: @name

  @doc """
  A scene's people as the row keeps them (seshat#57): each name trimmed,
  the empty dropped, a name given twice (in any case) kept once at its
  first spelling; nil is no one. Refused when an entry is no text or
  spans lines, a name runs past `name_max/0`, or more than
  `people_max/0` remain.
  """
  @spec people(term()) :: {:ok, [String.t()]} | {:error, Error.t()}
  def people(nil), do: {:ok, []}

  def people(names) when is_list(names) do
    if Enum.all?(names, &is_binary/1) do
      names
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq_by(&String.downcase/1)
      |> people_bounded()
    else
      people_refused()
    end
  end

  def people(_other), do: people_refused()

  defp people_bounded(names) do
    if length(names) <= @people_max and
         Enum.all?(
           names,
           &(String.length(&1) <= @name and not String.contains?(&1, ["\n", "\r"]))
         ),
       do: {:ok, names},
       else: people_refused()
  end

  defp people_refused,
    do:
      {:error,
       Error.new(:seshat_scene_invalid, :seshat_scene_people_invalid,
         detail:
           "people is a list of names, each one line of at most #{@name} characters, at most #{@people_max} of them"
       )}

  def execute(%__MODULE__{days: days}, %Commands.WriteScene{} = c) do
    with :ok <- day_ok(c.day),
         :ok <-
           scene_ok(%{
             "title" => c.title,
             "from_turn" => c.from_turn,
             "to_turn" => c.to_turn,
             "from_time" => iso(c.from_time),
             "to_time" => iso(c.to_time),
             "register" => c.register,
             "rounds_ran_out" => c.rounds_ran_out || false
           }),
         :ok <- summary_ok(c.summary),
         :ok <- mood_ok(c.mood),
         {:ok, people} <- people(c.people) do
      %Events.SceneWritten{
        actor: c.actor,
        at: c.at,
        id: c.id,
        day: c.day,
        number: count(days, c.day) + 1,
        title: String.trim(c.title),
        from_turn: String.trim(c.from_turn),
        to_turn: String.trim(c.to_turn),
        from_time: c.from_time,
        to_time: c.to_time,
        summary: String.trim(c.summary),
        mood: c.mood && String.trim(c.mood),
        rounds_ran_out: c.rounds_ran_out == true,
        register: c.register,
        people: people,
        written_on: c.today
      }
    end
  end

  def execute(%__MODULE__{days: days}, %Commands.CorrectScene{} = c) do
    with {:ok, scene} <- scene(days, c.day, c.number),
         {:ok, changes} <- changes_ok(c.changes),
         {:ok, changes} <- people_change(changes),
         :ok <- scene_ok(Map.merge(scene.facts, Map.delete(changes, "mood"))),
         :ok <- if(Map.has_key?(changes, "mood"), do: mood_ok(changes["mood"]), else: :ok) do
      current = Map.put(scene.facts, "mood", scene.mood)
      moved = Map.reject(changes, fn {field, value} -> current[field] == value end)

      if moved == %{} do
        []
      else
        %Events.SceneCorrected{
          actor: c.actor,
          at: c.at,
          note: c.note,
          id: c.id,
          day: c.day,
          number: c.number,
          changes: moved,
          was: Map.take(current, Map.keys(moved)),
          mood_correction:
            Map.has_key?(moved, "mood") and not is_nil(scene.mood_on) and
              scene.mood_on != c.today,
          written_on: c.today
        }
      end
    end
  end

  def execute(%__MODULE__{days: days}, %Commands.CorrectSceneSummary{} = c) do
    with {:ok, _scene} <- scene(days, c.day, c.corrects),
         :ok <-
           scene_ok(%{
             "title" => "correction",
             "from_turn" => c.from_turn,
             "to_turn" => c.to_turn,
             "rounds_ran_out" => false
           }),
         :ok <- summary_ok(c.summary) do
      %Events.SceneSummaryCorrected{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        day: c.day,
        number: count(days, c.day) + 1,
        corrects: c.corrects,
        from_turn: String.trim(c.from_turn),
        to_turn: String.trim(c.to_turn),
        summary: String.trim(c.summary)
      }
    end
  end

  def execute(%__MODULE__{days: days}, %Commands.CloseScenes{} = c) do
    with :ok <- day_ok(c.day) do
      if get_in(days, [c.day, :closed]) == true,
        do: [],
        else: %Events.ScenesClosed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          day: c.day,
          count: count(days, c.day)
        }
    end
  end

  def apply(%__MODULE__{} = s, %Events.SceneWritten{} = e) do
    facts = %{
      "title" => e.title,
      "from_turn" => e.from_turn,
      "to_turn" => e.to_turn,
      "from_time" => iso(e.from_time),
      "to_time" => iso(e.to_time),
      "register" => e.register,
      "rounds_ran_out" => e.rounds_ran_out,
      "people" => e.people || []
    }

    row = %{kind: "scene", facts: facts, mood: e.mood, mood_on: e.mood && e.written_on}
    put_row(%{s | id: e.id}, e.day, e.number, row)
  end

  def apply(%__MODULE__{} = s, %Events.SceneCorrected{} = e) do
    day = Map.fetch!(s.days, e.day)
    scene = Map.fetch!(day.scenes, e.number)
    changes = texts(e.changes)

    scene =
      case Map.fetch(changes, "mood") do
        {:ok, mood} ->
          %{scene | mood: mood, mood_on: scene.mood_on || (mood && e.written_on)}

        :error ->
          scene
      end

    scene = %{scene | facts: Map.merge(scene.facts, Map.delete(changes, "mood"))}
    %{s | days: Map.put(s.days, e.day, %{day | scenes: Map.put(day.scenes, e.number, scene)})}
  end

  def apply(%__MODULE__{} = s, %Events.SceneSummaryCorrected{} = e),
    do: put_row(s, e.day, e.number, %{kind: "correction", corrects: e.corrects})

  def apply(%__MODULE__{} = s, %Events.ScenesClosed{} = e) do
    day = Map.get(s.days, e.day, new_day())
    %{s | id: e.id, days: Map.put(s.days, e.day, %{day | closed: true})}
  end

  defp new_day, do: %{count: 0, closed: false, scenes: %{}}

  defp put_row(s, day, number, row) do
    d = Map.get(s.days, day, new_day())
    d = %{d | count: max(d.count, number), scenes: Map.put(d.scenes, number, row)}
    %{s | days: Map.put(s.days, day, d)}
  end

  defp count(days, day), do: days |> Map.get(day, new_day()) |> Map.fetch!(:count)

  defp scene(days, day, number) do
    case get_in(days, [day, :scenes, number]) do
      %{kind: "scene"} = scene ->
        {:ok, scene}

      _none ->
        {:error,
         Error.new(:seshat_no_such_scene, :seshat_scene_absent, day: inspect(day), number: number)}
    end
  end

  defp people_change(%{"people" => names} = changes) do
    with {:ok, people} <- people(names), do: {:ok, %{changes | "people" => people}}
  end

  defp people_change(changes), do: {:ok, changes}

  defp changes_ok(changes) when is_map(changes) and map_size(changes) > 0 do
    cond do
      Map.has_key?(changes, "summary") ->
        {:error, Error.new(:seshat_scene_summary_kept, :seshat_scene_summary_overwrite)}

      Enum.all?(Map.keys(changes), &(&1 in ["mood" | @facts])) ->
        {:ok, changes}

      true ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_change_unknown,
           detail: "a correction moves only #{Enum.join(["mood" | @facts], ", ")}"
         )}
    end
  end

  defp changes_ok(_none),
    do:
      {:error,
       Error.new(:seshat_scene_invalid, :seshat_scene_change_empty,
         detail: "a correction names at least one field to move"
       )}

  defp scene_ok(facts) do
    cond do
      not line?(facts["title"]) ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_title_invalid,
           detail: "a title is one line of at most #{@line} characters"
         )}

      not (ref?(facts["from_turn"]) and ref?(facts["to_turn"])) ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_turns_invalid,
           detail: "a scene cites its first and last turn by ref (from_turn, to_turn)"
         )}

      not times?(facts["from_time"], facts["to_time"]) ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_times_invalid,
           detail: "a span's times are instants, the first no later than the last"
         )}

      facts["register"] not in [nil | @registers] ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_register_invalid,
           detail: "a scene's register is his, hers or work, or none"
         )}

      not is_boolean(facts["rounds_ran_out"]) ->
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_rounds_invalid,
           detail: "rounds_ran_out is true or false"
         )}

      true ->
        :ok
    end
  end

  defp summary_ok(summary) do
    if is_binary(summary) and String.trim(summary) != "",
      do: :ok,
      else:
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_summary_invalid,
           detail: "a scene says in a few lines what happened in it"
         )}
  end

  defp mood_ok(nil), do: :ok

  defp mood_ok(mood) do
    if line?(mood),
      do: :ok,
      else:
        {:error,
         Error.new(:seshat_scene_invalid, :seshat_scene_mood_invalid,
           detail: "a mood is one line of at most #{@line} characters"
         )}
  end

  defp day_ok(day) do
    if is_binary(day) and match?({:ok, _}, Date.from_iso8601(day)),
      do: :ok,
      else: {:error, Error.new(:seshat_day_invalid, :seshat_scene_day_invalid, day: inspect(day))}
  end

  defp line?(text),
    do:
      is_binary(text) and String.trim(text) != "" and not String.contains?(text, "\n") and
        String.length(text) <= @line

  defp ref?(ref),
    do:
      is_binary(ref) and String.trim(ref) != "" and String.length(String.trim(ref)) <= @ref and
        not String.contains?(String.trim(ref), [" ", "\n", "\t"])

  defp times?(from, to) do
    with {:ok, a} <- instant(from),
         {:ok, b} <- instant(to) do
      is_nil(a) or is_nil(b) or DateTime.compare(a, b) != :gt
    else
      _bad -> false
    end
  end

  defp instant(nil), do: {:ok, nil}

  defp instant(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> {:ok, at}
      other -> other
    end
  end

  defp instant(_other), do: :error

  @doc "A history map keyed by text, as the log may hand it back keyed by atoms."
  @spec texts(map() | nil) :: map()
  def texts(nil), do: %{}
  def texts(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  @doc "An instant as the history keeps it: ISO 8601 to the second, nil for none."
  @spec iso(DateTime.t() | String.t() | nil) :: String.t() | nil
  def iso(nil), do: nil
  def iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  def iso(text) when is_binary(text), do: text
end
