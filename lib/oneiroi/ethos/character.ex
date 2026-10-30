defmodule Oneiroi.Ethos.Character do
  @moduledoc """
  The character aggregate on `ethos-<resident_id>` (spec §6.17). Pure:
  no clock, no randomness, no ids but the ones the resident aggregate
  minted. It holds the seeds with their states and the days they were
  cited, the habits as last revised, and the set of citations, so that
  a seed graduates toward a habit only once its citations confirm it
  across the required days, and a citation is recorded once.
  """

  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Events

  defstruct [:id, seeds: %{}, habits: %{}, citations: MapSet.new(), baseline_at: nil]

  @type t :: %__MODULE__{}

  @stances ~w(keep change)
  # The situation features a trigger may name (spec §6.3): the closed set
  # the assembler can match without a model call. `words` are the
  # witness's words, `tags` a tag present on the conversation, `times`
  # the time of day. The resident proposes additions, and that is a code
  # change here.
  @trigger_keys ~w(words tags times)
  @times ~w(morning afternoon evening night)
  @targets ~w(turn bookmark)
  # Where a seed may graduate to (P38's fork): a habit, a disposition
  # that needs behavioural citations; a position or a soul line, the
  # evaluative kinds, which need none.
  @graduations ~w(habit position soul)
  @name_limit 120
  # A seed is one short becoming, not an essay: the bound is a guess.
  @seed_limit 2_000

  @doc "The stances a habit takes: `keep` or `change`."
  @spec stances() :: [String.t()]
  def stances, do: @stances

  @doc "The times of day a trigger may name."
  @spec times() :: [String.t()]
  def times, do: @times

  @doc "The kinds a seed may graduate toward."
  @spec graduations() :: [String.t()]
  def graduations, do: @graduations

  @doc "Whether a trigger is well formed: a map of `words`, `tags` and `times` lists, at least one non-empty."
  @spec trigger_ok?(term()) :: boolean()
  def trigger_ok?(%{} = trigger) do
    keys = Map.keys(trigger)
    lists = Enum.map(@trigger_keys, &Map.get(trigger, &1, []))

    Enum.all?(keys, &(&1 in @trigger_keys)) and
      Enum.all?(lists, &(is_list(&1) and Enum.all?(&1, fn v -> is_binary(v) end))) and
      Enum.any?(lists, &(&1 != [])) and
      Enum.all?(Map.get(trigger, "times", []), &(&1 in @times))
  end

  def trigger_ok?(_other), do: false

  # ---- seeds ----

  def execute(%__MODULE__{seeds: seeds}, %Commands.PlantSeed{} = c) do
    cond do
      Map.has_key?(seeds, c.number) ->
        []

      not text_ok?(c.text, @seed_limit) ->
        {:error, :text_invalid}

      true ->
        %Events.SeedPlanted{actor: c.actor, at: c.at, id: c.id, number: c.number, text: c.text}
    end
  end

  def execute(%__MODULE__{seeds: seeds}, %Commands.WiltSeed{} = c) do
    with {:ok, _seed} <- open_seed(seeds, c.number),
         do: %Events.SeedWilted{actor: c.actor, at: c.at, id: c.id, number: c.number}
  end

  # Toward a habit only once confirmed across the required days (research
  # §3: if-then signatures are moderately reliable, so one burst of
  # citations is a hypothesis); toward an evaluative kind with no
  # behavioural evidence asked, because a taste is not a disposition.
  def execute(%__MODULE__{seeds: seeds}, %Commands.GraduateSeed{} = c) do
    with {:ok, seed} <- open_seed(seeds, c.number),
         :ok <- graduation_ok(c.to_kind),
         :ok <- confirmed(seed, c) do
      %Events.SeedGraduated{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        number: c.number,
        to_kind: c.to_kind,
        to_id: to_string(c.to_id)
      }
    end
  end

  def execute(%__MODULE__{} = s, %Commands.CiteSeed{} = c) do
    with {:ok, _seed} <- open_seed(s.seeds, c.number),
         :ok <- target_ok(c) do
      if MapSet.member?(s.citations, citation_key(:seed, c)),
        do: [],
        else: %Events.SeedCited{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          target_kind: c.target_kind,
          target_id: to_string(c.target_id)
        }
    end
  end

  # ---- habits ----

  def execute(%__MODULE__{habits: habits}, %Commands.DefineHabit{} = c) do
    cond do
      Map.has_key?(habits, c.number) ->
        []

      not text_ok?(c.name, @name_limit) ->
        {:error, :name_invalid}

      c.stance not in @stances ->
        {:error, :stance_invalid}

      not trigger_ok?(c.trigger) ->
        {:error, :trigger_invalid}

      true ->
        %Events.HabitDefined{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          name: c.name,
          trigger: c.trigger,
          stance: c.stance,
          seed_number: c.seed_number
        }
    end
  end

  def execute(%__MODULE__{habits: habits}, %Commands.ChangeHabit{} = c) do
    cond do
      not Map.has_key?(habits, c.number) ->
        {:error, :no_such_habit}

      not text_ok?(c.name, @name_limit) ->
        {:error, :name_invalid}

      c.stance not in @stances ->
        {:error, :stance_invalid}

      not trigger_ok?(c.trigger) ->
        {:error, :trigger_invalid}

      Map.get(habits, c.number) == %{name: c.name, trigger: c.trigger, stance: c.stance} ->
        []

      true ->
        %Events.HabitChanged{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          name: c.name,
          trigger: c.trigger,
          stance: c.stance
        }
    end
  end

  def execute(%__MODULE__{habits: habits}, %Commands.AffirmHabit{} = c) do
    if Map.has_key?(habits, c.number),
      do: %Events.HabitAffirmed{
        actor: c.actor,
        at: c.at,
        note: c.note,
        id: c.id,
        number: c.number
      },
      else: {:error, :no_such_habit}
  end

  def execute(%__MODULE__{} = s, %Commands.CiteHabit{} = c) do
    cond do
      not Map.has_key?(s.habits, c.number) ->
        {:error, :no_such_habit}

      c.target_kind not in @targets ->
        {:error, :target_invalid}

      MapSet.member?(s.citations, citation_key(:habit, c)) ->
        []

      true ->
        %Events.HabitCited{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          target_kind: c.target_kind,
          target_id: to_string(c.target_id)
        }
    end
  end

  # A soul line's citation: the target's kind is checked here, the line
  # at the edge (it is not this aggregate's state), and a citation is a
  # set, so the same moment cited twice is once.
  def execute(%__MODULE__{} = s, %Commands.CiteSoulLine{} = c) do
    with :ok <- target_ok(c) do
      if MapSet.member?(s.citations, citation_key(:soul, c)),
        do: [],
        else: %Events.SoulLineCited{
          actor: c.actor,
          at: c.at,
          id: c.id,
          number: c.number,
          target_kind: c.target_kind,
          target_id: to_string(c.target_id)
        }
    end
  end

  # A baseline is taken once per interval: the second within it is
  # refused, so the nightly pass asking every day lands one a week.
  def execute(%__MODULE__{baseline_at: last}, %Commands.TakeBaseline{} = c) do
    if last && DateTime.diff(c.at, last, :day) < c.interval_days,
      do: {:error, :baseline_fresh},
      else: %Events.BaselineTaken{
        actor: c.actor,
        at: c.at,
        id: c.id,
        habits: c.habits,
        spread: c.spread,
        breadth: c.breadth
      }
  end

  # ---- apply ----

  def apply(%__MODULE__{} = s, %Events.SeedPlanted{} = e),
    do: %{s | id: e.id, seeds: Map.put(s.seeds, e.number, %{state: :open, days: MapSet.new()})}

  def apply(%__MODULE__{} = s, %Events.SeedWilted{} = e),
    do: put_in(s.seeds[e.number].state, :wilted)

  def apply(%__MODULE__{} = s, %Events.SeedGraduated{} = e),
    do: put_in(s.seeds[e.number].state, :graduated)

  # `update_in` on a path from the struct returns the whole struct, not
  # the field: the first version assigned that struct to `seeds` and lost
  # every citation, which the pure test caught on the second cite.
  def apply(%__MODULE__{} = s, %Events.SeedCited{} = e) do
    day = Date.to_iso8601(DateTime.to_date(e.at))
    s = update_in(s.seeds[e.number].days, &MapSet.put(&1, day))
    %{s | citations: MapSet.put(s.citations, citation_key(:seed, e))}
  end

  def apply(%__MODULE__{} = s, %Events.HabitDefined{} = e),
    do: %{s | id: e.id, habits: Map.put(s.habits, e.number, habit_state(e))}

  def apply(%__MODULE__{} = s, %Events.HabitChanged{} = e),
    do: %{s | habits: Map.put(s.habits, e.number, habit_state(e))}

  def apply(%__MODULE__{} = s, %Events.HabitAffirmed{}), do: s

  def apply(%__MODULE__{} = s, %Events.HabitCited{} = e),
    do: %{s | citations: MapSet.put(s.citations, citation_key(:habit, e))}

  def apply(%__MODULE__{} = s, %Events.SoulLineCited{} = e),
    do: %{s | citations: MapSet.put(s.citations, citation_key(:soul, e))}

  def apply(%__MODULE__{} = s, %Events.BaselineTaken{} = e), do: %{s | baseline_at: e.at}

  # ---- helpers ----

  defp open_seed(seeds, number) do
    case Map.get(seeds, number) do
      nil -> {:error, :no_such_seed}
      %{state: :open} = seed -> {:ok, seed}
      _closed -> {:error, :seed_closed}
    end
  end

  defp graduation_ok(kind),
    do: if(kind in @graduations, do: :ok, else: {:error, :graduation_invalid})

  defp confirmed(seed, %{to_kind: "habit", required: required}) when is_integer(required) do
    if MapSet.size(seed.days) >= required,
      do: :ok,
      else: {:error, {:unconfirmed, MapSet.size(seed.days), required}}
  end

  defp confirmed(_seed, _c), do: :ok

  defp target_ok(%{target_kind: kind}) when kind in @targets, do: :ok
  defp target_ok(_c), do: {:error, :target_invalid}

  defp citation_key(kind, %{number: number, target_kind: target_kind, target_id: id}),
    do: {kind, number, target_kind, to_string(id)}

  defp habit_state(e), do: %{name: e.name, trigger: e.trigger, stance: e.stance}

  defp text_ok?(text, limit),
    do: is_binary(text) and String.trim(text) != "" and String.length(text) <= limit
end
