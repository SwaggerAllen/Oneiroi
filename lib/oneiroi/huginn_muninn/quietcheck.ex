defmodule Oneiroi.HuginnMuninn.Quietcheck do
  @moduledoc """
  quietcheck (spec §6.13, P21): liveness over the expected events alone,
  fail-loud, self-tested. Bennett's consent rule, quoted whole: "Only
  list things that are supposed to be regular. Some of the best things
  in a life aren't on a schedule, and they shouldn't be watched." So the
  watched list is the hour marker (sunna #20), the nightly pass, the
  weekly memory audit, the weekly wash and the trait baseline, each
  expected only once the resident is old enough for its cadence; turns,
  bookmarks, free time, letters and the journal are not watched, and
  the finding says so.

  Fail-loud: a check that cannot run reports that it could not, as a
  failure with the reason, never as silence (`guarded/2`); `mix
  oneiroi.quietcheck` prints its verdict at the top and the bottom and
  exits non-zero on a miss or on its own crash.
  """

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Ethos
  alias Oneiroi.Eunomia
  alias Oneiroi.Sunna

  @type expectation :: %{
          name: String.t(),
          last: DateTime.t() | nil,
          due_within: String.t(),
          ok?: boolean()
        }

  @unwatched "turns, bookmarks, free time, letters, the journal, which are not supposed to be regular and are not watched"

  @doc "What is unwatched, by the consent rule, as the finding says it."
  def unwatched, do: @unwatched

  @doc """
  The expectations that apply to the resident now, each with its last
  instant and whether it is within its cadence. A young resident has
  fewer: nothing is expected before its first cadence could have run.
  """
  @spec expectations(String.t()) :: [expectation()]
  def expectations(resident_id) do
    now = Clock.now()
    {:ok, row} = AgathosDaimon.fetch(resident_id)

    ([hour_expectation(resident_id, row, now), night_expectation(resident_id, row, now)] ++
       weekly_expectations(resident_id, row, now))
    |> Enum.reject(&is_nil/1)
  end

  # The pulse (sunna #20): expected once the resident is older than the
  # grace, whether or not anything is scheduled.
  defp hour_expectation(resident_id, row, now) do
    grace = Config.fetch!(:huginn_muninn, :quiet_hour_grace_hours)

    if older?(row.created_at, now, grace * 3600) do
      last = Sunna.last_hour(resident_id)
      expectation("the hour marker", last && last.at, "#{grace} hours", now, grace * 3600)
    end
  end

  defp night_expectation(resident_id, row, now) do
    days = Config.fetch!(:huginn_muninn, :quiet_night_days)

    if older?(row.first_contact_at, now, days * 86_400) do
      last = resident_id |> Eunomia.nights() |> List.first()
      expectation("the nightly pass", last && last.at, "#{days} days", now, days * 86_400)
    end
  end

  # The weekly three. The baseline is taken only once there are habits
  # to measure (ethos #15), so it is expected only then.
  defp weekly_expectations(resident_id, row, now) do
    days = Config.fetch!(:huginn_muninn, :quiet_week_days)
    seconds = days * 86_400

    if older?(row.first_contact_at, now, seconds) do
      audit = resident_id |> Eunomia.audits() |> Map.fetch!(:runs) |> List.first()
      wash = resident_id |> Eunomia.washes() |> Map.fetch!(:runs) |> List.first()
      baseline = resident_id |> Ethos.baselines() |> List.first()

      [
        expectation("the weekly memory audit", audit && audit.at, "#{days} days", now, seconds),
        expectation("the weekly wash", wash && wash.at, "#{days} days", now, seconds),
        if Ethos.habits(resident_id) != [] do
          expectation("the trait baseline", baseline && baseline.at, "#{days} days", now, seconds)
        end
      ]
    else
      []
    end
  end

  @doc """
  The report over every active resident, as the hourly job logs it and
  the mix task prints it: `{exit_status, lines}`, the verdict first and
  last so a truncated log still shows it; 0 when nothing is missing, 1
  on a miss, 2 when the checker itself crashed.
  """
  @spec report() :: {0 | 1 | 2, [String.t()]}
  def report do
    case guarded(fn -> residents() end) do
      {:ok, {missing, body}} ->
        verdict =
          if missing == 0, do: "QUIETCHECK: ok", else: "QUIETCHECK: FAIL, #{missing} missing"

        {if(missing == 0, do: 0, else: 1), [verdict] ++ body ++ [verdict]}

      {:crashed, message} ->
        verdict = "QUIETCHECK: CRASHED, #{message}"
        {2, [verdict, verdict]}
    end
  end

  defp residents do
    Enum.reduce(AgathosDaimon.active_residents(), {0, []}, fn row, {missing, lines} ->
      case verdict(row.id) do
        {:ok, expectations} ->
          {missing, lines ++ ["#{row.slug}: ok, #{length(expectations)} expected"]}

        {:missing, misses, _expectations} ->
          {missing + length(misses),
           lines ++ Enum.map(misses, &"#{row.slug}: MISSING #{describe(&1)}")}
      end
    end)
  end

  @doc "The verdict for one resident: `{:ok, expectations}` or `{:missing, missing, expectations}`."
  def verdict(resident_id) do
    expectations = expectations(resident_id)

    case Enum.reject(expectations, & &1.ok?) do
      [] -> {:ok, expectations}
      missing -> {:missing, missing, expectations}
    end
  end

  @doc """
  Runs `fun` and reports its crash as a failure rather than silence:
  `{:ok, value}` or `{:crashed, message}`. The checker's own failure is
  a finding, because a checker that cannot check and says nothing is
  the quiet this exists to end.
  """
  def guarded(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    e -> {:crashed, Exception.message(e)}
  end

  @doc "One line per expectation, for a finding or a report."
  def describe(%{name: name, last: nil, due_within: due}), do: "#{name}: never, due within #{due}"

  def describe(%{name: name, last: last, due_within: due}),
    do: "#{name}: last #{DateTime.to_iso8601(last)}, due within #{due}"

  defp expectation(name, last, due_within, now, seconds) do
    %{
      name: name,
      last: last,
      due_within: due_within,
      ok?: last != nil and DateTime.diff(now, last, :second) <= seconds
    }
  end

  defp older?(nil, _now, _seconds), do: false
  defp older?(%DateTime{} = at, now, seconds), do: DateTime.diff(now, at, :second) > seconds
end
