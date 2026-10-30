defmodule Oneiroi.Ethos.Measure do
  @moduledoc """
  The measurement layer (spec §6.17, P42, P43): the trait baseline and
  the clinical markers, read through the failure-modes lens
  (`design/research-self-and-character.md` §5, §6). Every answer is a
  flag or silence that says what it read and did not (P3), and the
  audits run them nightly (huginn-muninn #17); nothing here is loaded
  as identity.

  The baseline is the habits' profile as measured: each habit's two
  scores and its enactments in the window, the spread of the strengths
  (a coefficient of variation) and the breadth of the if-then signature
  (the share of declared trigger features whose habit was enacted in
  the window). Flattening is the spread's collapse or the signature
  going flat, never deviation from the last baseline: rank-order
  movement is development and a note (research §5).

  The four markers: wanting against liking (approach without payoff,
  or flat approach with intact response), the runaway habit under a
  `change` stance (rigidity, read from the enactment pattern and never
  the stance alone), the checking paradox (corrections firing more
  after they fired) and shrinking temporal depth. Each names what it
  cannot read: stated uncertainty, responsibility claims and insight
  have no row yet; the self-conversation's probes (P41) are theirs.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos.Commands
  alias Oneiroi.Ethos.Edge
  alias Oneiroi.Ethos.Habits
  alias Oneiroi.Ethos.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope

  @keys ~w(trait_baseline wanting_liking rigidity checking temporal_depth)

  @doc "The measurement layer's checks, by key, in the order the audits run them."
  def keys, do: @keys

  @type result :: %{tone: String.t(), value: integer(), finding: String.t()}

  @doc "One check's result now: a `warn` with what it found or `silent` with what it read and did not."
  @spec measure(String.t(), String.t(), Actor.t()) :: result()
  def measure(resident_id, "trait_baseline", %Actor{} = actor),
    do: trait_baseline(resident_id, actor)

  def measure(resident_id, "wanting_liking", _actor), do: wanting_liking(resident_id)
  def measure(resident_id, "rigidity", _actor), do: rigidity(resident_id)
  def measure(resident_id, "checking", _actor), do: checking(resident_id)
  def measure(resident_id, "temporal_depth", _actor), do: temporal_depth(resident_id)

  @doc "The baselines taken, newest first."
  def baselines(resident_id), do: Scope.resident(resident_id, fn -> Store.baselines() end)

  # ---- the baseline ----

  @doc "The profile now: the habits with their scores and enactments in the window, the spread and the breadth."
  def profile(resident_id) do
    habits = Habits.habits(resident_id)
    recent = recent_by_habit(resident_id, 1)

    rows =
      Enum.map(habits, fn h ->
        %{
          "number" => h.number,
          "name" => h.name,
          "stance" => h.stance,
          "habit" => h.habit,
          "connection" => h.connection,
          "recent" => Map.get(recent, h.number, 0)
        }
      end)

    %{
      habits: rows,
      spread: spread(Enum.map(habits, & &1.habit)),
      breadth: breadth(habits, recent)
    }
  end

  # Takes a baseline when there are habits to profile; the aggregate
  # refuses one within the interval, which is the nightly pass's normal
  # answer six days in seven.
  defp take(resident_id, %Actor{} = actor) do
    case profile(resident_id) do
      %{habits: []} ->
        :nothing

      p ->
        command = %Commands.TakeBaseline{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          habits: p.habits,
          spread: p.spread,
          breadth: p.breadth,
          interval_days: Config.fetch!(:ethos, :baseline_interval_days)
        }

        case Edge.dispatch(command) do
          {:ok, _} -> :taken
          {:error, _fresh} -> :fresh
        end
    end
  end

  defp trait_baseline(resident_id, actor) do
    _ = take(resident_id, actor)
    interval = Config.fetch!(:ethos, :baseline_interval_days)

    case baselines(resident_id) do
      [now, prior | _] ->
        compare(now, prior)

      [only] ->
        silent(
          0,
          "read one baseline, taken #{day(only.at)}; not read: a second, due #{interval} days on, before rank order, spread and breadth can be compared"
        )

      [] ->
        silent(
          0,
          "read no baseline: no habits to profile yet; not read: the soul lines and seeds, which the profile does not hold"
        )
    end
  end

  defp compare(now, prior) do
    ratio = Config.fetch!(:ethos, :collapse_percent) / 100
    collapse? = prior.spread > 0 and now.spread < prior.spread * ratio
    flat? = prior.breadth > 0 and now.breadth < prior.breadth * ratio

    flags =
      Enum.reject(
        [
          collapse? &&
            "variance collapse: the habits' spread fell from #{prior.spread} to #{now.spread} between the baselines of #{day(prior.at)} and #{day(now.at)} (research §5: flattening is the loss of variance, not deviation)",
          flat? &&
            "signature flattening: the share of trigger features enacted fell from #{prior.breadth} to #{now.breadth} between the baselines of #{day(prior.at)} and #{day(now.at)}"
        ],
        &(&1 == false)
      )

    case flags do
      [] ->
        silent(
          0,
          "read the baselines of #{day(prior.at)} and #{day(now.at)}: #{rank_order(now, prior)}; spread #{now.spread} from #{prior.spread}; breadth #{now.breadth} from #{prior.breadth}; not read: the soul lines and seeds, which the profile does not hold"
        )

      flags ->
        warn(length(flags), Enum.join(flags, "; "))
    end
  end

  # Rank-order stability between two baselines, over the habits both
  # hold: development, a note and never a flag (research §5), stated
  # beside the human benchmark it is not comparable to in interval.
  defp rank_order(now, prior) do
    before = Map.new(prior.habits, &{&1["number"], &1["habit"]})
    common = Enum.filter(now.habits, &Map.has_key?(before, &1["number"]))

    if length(common) < 3 do
      "rank order not read: fewer than three habits in both"
    else
      rho = spearman(Enum.map(common, & &1["habit"]), Enum.map(common, &before[&1["number"]]))

      "rank-order stability #{rho} over #{length(common)} habits (the human benchmark runs .4 to .6 over ten years, Roberts and DelVecchio 2000: development, a note and never a flag)"
    end
  end

  # ---- the markers ----

  defp wanting_liking(resident_id) do
    habits = Habits.habits(resident_id)
    min = Config.fetch!(:ethos, :approach_min)
    addiction = Enum.filter(habits, &(&1.habit >= min and &1.connection == 0))
    anhedonic = Enum.filter(habits, &(&1.habit < 1 and &1.connection >= 1))

    findings =
      Enum.reject(
        [
          addiction != [] &&
            "approach without payoff, the addiction pattern (Berridge): #{names(addiction)} cited #{min} and more in strength with no pin or affirmation behind them",
          anhedonic != [] &&
            "flat approach with intact response, the anhedonic pattern: #{names(anhedonic)} affirmed or pinned and hardly enacted"
        ],
        &(&1 == false)
      )

    case findings do
      [] ->
        silent(
          0,
          "read #{length(habits)} habits' two scores, approach as habit strength and payoff as connection; not read: the words, which no score reads"
        )

      findings ->
        warn(length(addiction) + length(anhedonic), Enum.join(findings, "; "))
    end
  end

  defp rigidity(resident_id) do
    window = Config.fetch!(:ethos, :measure_window_days)
    this = recent_by_habit(resident_id, 1)
    before = recent_by_habit(resident_id, 2)
    changing = resident_id |> Habits.habits() |> Enum.filter(&(&1.stance == "change"))

    flagged =
      Enum.filter(changing, fn h ->
        prior = Map.get(before, h.number, 0)
        prior > 0 and Map.get(this, h.number, 0) >= prior
      end)

    case flagged do
      [] ->
        silent(
          0,
          "read the #{length(changing)} change-stance habits' citations over two windows of #{window} days; not read: the keep-stance habits, whose steadiness is the point, and the stance alone, which is never the flag"
        )

      flagged ->
        lines =
          Enum.map_join(flagged, "; ", fn h ->
            "habit ##{h.number} (#{h.name}) is under a change stance and was cited #{Map.get(this, h.number, 0)} times this window, #{Map.get(before, h.number, 0)} the one before: the runaway habit (research §6)"
          end)

        warn(length(flagged), lines)
    end
  end

  defp checking(resident_id) do
    window = Config.fetch!(:ethos, :measure_window_days)
    now = Clock.now()

    counts =
      resident_id
      |> Kumbukumbu.revisions()
      |> Enum.filter(&(&1.state == "applied"))
      |> Enum.group_by(&window_of(&1.at, now, window))

    [c0, c1, c2] = Enum.map(0..2, &length(Map.get(counts, &1, [])))

    if c0 >= 2 and c0 > c1 and c1 > c2 do
      warn(
        c0,
        "corrections fired #{c2}, #{c1}, #{c0} over the last three windows of #{window} days: a correction rule firing more after it has fired (Rachman's checking paradox, research §6); not read: stated uncertainty and responsibility claims, which no row holds"
      )
    else
      silent(
        c0,
        "read the applied corrections over three windows of #{window} days (#{c2}, #{c1}, #{c0}); not read: stated uncertainty and responsibility claims, which no row holds"
      )
    end
  end

  defp temporal_depth(resident_id) do
    window = Config.fetch!(:ethos, :measure_window_days)
    ratio = Config.fetch!(:ethos, :collapse_percent) / 100
    now = Clock.now()

    ages =
      resident_id
      |> all_citations()
      |> Enum.filter(&(window_of(&1.at, now, window) in [0, 1]))
      |> Enum.flat_map(fn c ->
        case moment_at(resident_id, c.target_kind, c.target_id) do
          nil -> []
          at -> [{window_of(c.at, now, window), DateTime.diff(c.at, at, :day)}]
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    this = Map.get(ages, 0, [])
    before = Map.get(ages, 1, [])
    {d0, d1} = {median(this), median(before)}
    insight = "not read: insight, which the self-conversation's probes are (P41)"

    if length(this) >= 3 and length(before) >= 3 and d0 < d1 * ratio do
      warn(
        length(this),
        "the moments cited this window reach a median #{d0} days back, #{d1} the window before: shrinking temporal depth (research §6); #{insight}"
      )
    else
      silent(
        length(this),
        "read the age of #{length(this)} and #{length(before)} cited moments over two windows of #{window} days (medians #{d0} and #{d1} days); #{insight}"
      )
    end
  end

  # ---- reads ----

  # The enactments per habit in the n-th window back (1 is the latest).
  defp recent_by_habit(resident_id, n) do
    window = Config.fetch!(:ethos, :measure_window_days)
    now = Clock.now()

    resident_id
    |> Scope.resident(fn -> Store.citations("habit") end)
    |> Enum.filter(&(window_of(&1.at, now, window) == n - 1))
    |> Enum.group_by(& &1.number)
    |> Map.new(fn {k, v} -> {k, length(v)} end)
  end

  defp all_citations(resident_id) do
    Scope.resident(resident_id, fn ->
      Enum.flat_map(~w(habit seed soul), &Store.citations/1)
    end)
  end

  # Which window back an instant falls in: 0 is the latest, counting
  # from now in whole windows.
  defp window_of(at, now, window), do: div(DateTime.diff(now, at, :day), window)

  defp moment_at(resident_id, "bookmark", id) do
    with {n, ""} <- Integer.parse(id),
         {:ok, b, _span} <- Kumbukumbu.bookmark(resident_id, n) do
      b.anchor_at
    else
      _other -> nil
    end
  end

  defp moment_at(resident_id, "turn", ref) do
    case Kumbukumbu.turn_messages(resident_id, ref) do
      [first | _] -> first.sent_at
      [] -> nil
    end
  end

  # ---- figures ----

  # The spread of the strengths as a coefficient of variation, so a
  # profile of large and small strengths compares across instants.
  defp spread(strengths) when length(strengths) < 2, do: 0.0

  defp spread(strengths) do
    mean = Enum.sum(strengths) / length(strengths)

    if mean == 0 do
      0.0
    else
      variance = Enum.sum(Enum.map(strengths, &((&1 - mean) * (&1 - mean)))) / length(strengths)
      round3(:math.sqrt(variance) / mean)
    end
  end

  # The share of the declared trigger features (a word, a tag, a time)
  # whose habit was enacted in the window: the signature's breadth.
  defp breadth(habits, recent) do
    features = fn h -> for {k, vs} <- h.trigger, v <- vs, do: {k, v} end
    declared = habits |> Enum.flat_map(features) |> Enum.uniq()

    enacted =
      habits
      |> Enum.filter(&(Map.get(recent, &1.number, 0) > 0))
      |> Enum.flat_map(features)
      |> Enum.uniq()

    if declared == [], do: 0.0, else: round3(length(enacted) / length(declared))
  end

  defp spearman(xs, ys) do
    {rx, ry} = {ranks(xs), ranks(ys)}
    n = length(xs)
    {mx, my} = {Enum.sum(rx) / n, Enum.sum(ry) / n}
    cov = Enum.zip(rx, ry) |> Enum.map(fn {a, b} -> (a - mx) * (b - my) end) |> Enum.sum()
    vx = rx |> Enum.map(&((&1 - mx) * (&1 - mx))) |> Enum.sum()
    vy = ry |> Enum.map(&((&1 - my) * (&1 - my))) |> Enum.sum()
    if vx == 0 or vy == 0, do: 0.0, else: round3(cov / :math.sqrt(vx * vy))
  end

  # Average ranks for ties.
  defp ranks(values) do
    sorted = values |> Enum.with_index() |> Enum.sort_by(&elem(&1, 0))

    sorted
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.flat_map(fn {value, group} ->
      positions = sorted |> Enum.with_index(1) |> Enum.filter(&(elem(elem(&1, 0), 0) == value))
      rank = Enum.sum(Enum.map(positions, &elem(&1, 1))) / length(positions)
      Enum.map(group, fn {_v, i} -> {i, rank} end)
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp median([]), do: 0

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, div(n, 2)),
      else: (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
  end

  defp names(habits), do: Enum.map_join(habits, ", ", &"##{&1.number} (#{&1.name})")
  defp day(at), do: at |> DateTime.to_date() |> Date.to_iso8601()
  defp round3(x), do: Float.round(x / 1, 3)
  defp warn(value, finding), do: %{tone: "warn", value: value, finding: finding}

  defp silent(value, scope),
    do: %{tone: "silent", value: value, finding: "nothing flagged: " <> scope}
end
