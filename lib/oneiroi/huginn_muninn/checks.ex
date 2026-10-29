defmodule Oneiroi.HuginnMuninn.Checks do
  @moduledoc """
  The audits (spec §6.13, F48, F49): the built-in checklist and the
  steward's own rules over figures, each run recording a result with a
  tone, and the check-engine light as the failing results of the audits
  that count. Audits read rows (the backup's attestation, open capture
  failures, failed syncs, missed check-ins, overdue predictions, the
  figures) and never transcript text; results are private to the dyad.

  The coherence work ships as this runnable checklist first (spec §6.13);
  citation drift and the journal's delta join it with the library.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Eunomia
  alias Oneiroi.HuginnMuninn.Audits
  alias Oneiroi.HuginnMuninn.Commands
  alias Oneiroi.HuginnMuninn.Error
  alias Oneiroi.HuginnMuninn.Figures
  alias Oneiroi.HuginnMuninn.Router
  alias Oneiroi.HuginnMuninn.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Proteus
  alias Oneiroi.Scope
  alias Oneiroi.Sunna

  @builtin [
    %{key: "attestation", label: "The last backup's root matched its commit", counts: true},
    %{key: "capture_failures", label: "No capture failure is waiting on you", counts: true},
    %{key: "sync_failures", label: "The last turns reached Honcho", counts: true},
    %{key: "missed_checkins", label: "Check-ins fired this week", counts: false},
    %{key: "overdue_predictions", label: "No prediction is past due unresolved", counts: false}
  ]

  @doc "The built-in audits: key, label, whether each counts toward the light."
  def builtin, do: @builtin

  # ---- the steward's audits ----

  @doc "Defines a steward's audit: a rule over a figure (`figure op value`), a tone when it fails, whether it counts."
  def define(resident_id, attrs, %Actor{} = actor) do
    with :ok <- steward_only(actor) do
      command = %Commands.DefineUserAudit{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: attrs[:key],
        label: attrs[:label],
        figure: attrs[:figure],
        op: attrs[:op],
        value: attrs[:value],
        tone: attrs[:tone] || "warn",
        counts: Map.get(attrs, :counts, true)
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  def retire(resident_id, key, %Actor{} = actor) do
    with :ok <- steward_only(actor) do
      command = %Commands.RetireUserAudit{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        key: key
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  # ---- running ----

  @doc "Runs every audit, built-in and the steward's, recording each result; returns the light."
  def run(resident_id, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id) do
      results =
        Enum.map(@builtin, &builtin_result(&1, resident_id, row)) ++ user_results(resident_id)

      Enum.each(results, fn r ->
        {:ok, _} =
          dispatch(%Commands.RecordRun{
            actor: actor,
            at: Clock.now(),
            id: resident_id,
            key: r.key,
            builtin: r.builtin,
            tone: r.tone,
            value: r.value,
            finding: r.finding
          })
      end)

      {:ok, light(resident_id)}
    end
  end

  defp builtin_result(%{key: "attestation"} = a, _resident_id, row) do
    case row.root_mismatched_at do
      nil ->
        result(a, "ok", 0, "the last backup's root matched")

      at ->
        result(
          a,
          "fail",
          1,
          "the root did not match at #{DateTime.to_iso8601(at)} (spec §6.10, F38)"
        )
    end
  end

  defp builtin_result(%{key: "capture_failures"} = a, resident_id, _row) do
    open = length(Kumbukumbu.failures({:resident, resident_id}))

    if open == 0,
      do: result(a, "ok", 0, "no capture failure is open"),
      else:
        result(
          a,
          "fail",
          open,
          "#{open} capture #{plural(open, "failure")} waiting to be retried or marked lost"
        )
  end

  defp builtin_result(%{key: "sync_failures"} = a, resident_id, _row) do
    failed = resident_id |> Proteus.syncs(20) |> Enum.count(&(&1.outcome == "failed"))

    if failed == 0,
      do: result(a, "ok", 0, "the last turns reached Honcho, or none have been synced yet"),
      else: result(a, "fail", failed, "#{failed} of the last 20 turns did not reach Honcho")
  end

  defp builtin_result(%{key: "missed_checkins"} = a, resident_id, _row) do
    missed = resident_id |> Sunna.firings(7) |> Enum.count(&(&1.outcome == "missed"))
    bound = Config.fetch!(:huginn_muninn, :missed_checkins_warn)

    if missed < bound,
      do: result(a, "ok", missed, "#{missed} check-#{plural(missed, "in")} missed this week"),
      else:
        result(a, "warn", missed, "#{missed} check-ins missed this week, #{bound} or more warns")
  end

  defp builtin_result(%{key: "overdue_predictions"} = a, resident_id, _row) do
    now = Clock.now()

    overdue =
      resident_id
      |> Eunomia.predictions()
      |> Map.fetch!(:open)
      |> Enum.count(&(DateTime.compare(&1.due, now) == :lt))

    if overdue == 0,
      do: result(a, "ok", 0, "no prediction is past due"),
      else:
        result(
          a,
          "warn",
          overdue,
          "#{overdue} #{plural(overdue, "prediction")} past due and unresolved; resolve them right, wrong or void"
        )
  end

  defp user_results(resident_id) do
    figures = Figures.figures(resident_id)

    resident_id
    |> Scope.resident(fn -> Store.audits() end)
    |> Enum.map(&user_result(&1, Enum.find(figures, fn f -> f.key == &1.figure end)))
  end

  defp user_result(audit, nil) do
    %{
      key: audit.key,
      builtin: false,
      tone: audit.tone,
      value: nil,
      finding: "figure #{audit.figure} does not exist"
    }
  end

  defp user_result(audit, figure) do
    if holds?(figure.value, audit.op, audit.value),
      do: %{
        key: audit.key,
        builtin: false,
        tone: "ok",
        value: figure.value,
        finding: "#{audit.label}: #{figure.value} #{audit.op} #{audit.value} holds"
      },
      else: %{
        key: audit.key,
        builtin: false,
        tone: audit.tone,
        value: figure.value,
        finding: "#{audit.label}: #{figure.value} is not #{audit.op} #{audit.value}"
      }
  end

  defp holds?(v, ">=", n), do: v >= n
  defp holds?(v, "<=", n), do: v <= n
  defp holds?(v, "==", n), do: v == n
  defp holds?(v, ">", n), do: v > n
  defp holds?(v, "<", n), do: v < n

  # ---- the light ----

  @doc """
  The check-engine light (F49): the latest result of every audit, and
  the findings list as the failing results of the audits that count;
  `state` is fail if any counting audit fails, warn if any warns, ok.
  """
  def light(resident_id) do
    counting = counting_keys(resident_id)

    latest =
      resident_id
      |> Scope.resident(fn -> Store.latest_runs() end)
      |> Enum.map(
        &%{
          key: &1.key,
          builtin: &1.builtin,
          tone: &1.tone,
          value: &1.value,
          finding: &1.finding,
          at: &1.at,
          counts: MapSet.member?(counting, &1.key)
        }
      )

    findings = Enum.filter(latest, &(&1.counts and &1.tone != "ok"))

    state =
      cond do
        Enum.any?(findings, &(&1.tone == "fail")) -> "fail"
        findings != [] -> "warn"
        true -> "ok"
      end

    %{state: state, findings: findings, results: latest}
  end

  @doc "Every audit, built-in and the steward's, with its last result."
  def audits(resident_id) do
    latest =
      resident_id |> Scope.resident(fn -> Store.latest_runs() end) |> Map.new(&{&1.key, &1})

    user = Scope.resident(resident_id, fn -> Store.audits() end)

    Enum.map(@builtin, &Map.merge(&1, %{builtin: true, last: Map.get(latest, &1.key)})) ++
      Enum.map(
        user,
        &%{
          key: &1.key,
          label: &1.label,
          builtin: false,
          figure: &1.figure,
          op: &1.op,
          value: &1.value,
          tone: &1.tone,
          counts: &1.counts,
          last: Map.get(latest, &1.key)
        }
      )
  end

  defp counting_keys(resident_id) do
    user =
      resident_id
      |> Scope.resident(fn -> Store.audits() end)
      |> Enum.filter(& &1.counts)
      |> Enum.map(& &1.key)

    builtin = @builtin |> Enum.filter(& &1.counts) |> Enum.map(& &1.key)
    MapSet.new(builtin ++ user)
  end

  # ---- helpers ----

  defp result(audit, tone, value, finding),
    do: %{key: audit.key, builtin: true, tone: tone, value: value, finding: finding}

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, :no_such_resident}
    end
  end

  defp steward_only(%Actor{kind: :steward}), do: :ok
  defp steward_only(%Actor{}), do: {:error, Error.new(:huginn_muninn_not_the_steward)}

  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, :key_invalid} ->
        {:error, Error.new(:huginn_muninn_key_invalid)}

      {:error, :label_invalid} ->
        {:error, Error.new(:huginn_muninn_label_invalid)}

      {:error, :rule_invalid} ->
        {:error, Error.new(:huginn_muninn_rule_invalid, ops: Audits.ops(), tones: Audits.tones())}

      {:error, :no_such_audit} ->
        {:error, Error.new(:huginn_muninn_no_such_audit, key: command.key)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
