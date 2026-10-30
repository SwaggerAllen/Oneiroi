defmodule Oneiroi.HuginnMuninn.Checks do
  @moduledoc """
  The audits (spec §6.13, F48, F49): the built-in checklist and the
  witness's own rules over figures, each run recording a result with a
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
  alias Oneiroi.Ethos
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
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

  @builtin [
    %{key: "attestation", label: "The last backup's root matched its commit", counts: true},
    %{key: "capture_failures", label: "No capture failure is waiting on you", counts: true},
    %{key: "sync_failures", label: "The last turns reached Honcho", counts: true},
    %{key: "missed_checkins", label: "Check-ins fired this week", counts: false},
    %{key: "overdue_predictions", label: "No prediction is past due unresolved", counts: false},
    %{key: "citation_drift", label: "Every citation that once resolved still does", counts: true},
    %{key: "journal_delta", label: "Planned days were wrapped", counts: false},
    %{key: "contract_due", label: "The agreement is within its year", counts: false},
    %{
      key: "corpus_shape",
      label: "The month's memory holds more than corrections",
      counts: false
    },
    %{key: "wash_flags", label: "No wash flag waits on the resident", counts: false},
    # The measurement layer (spec §6.17, P42, P43; ethos #15): the
    # character layer answers these, flag or silence; none counts toward
    # the light, because the clinical material is a design warning for
    # the layer and never a description of the resident.
    %{
      key: "trait_baseline",
      label: "The habits' spread and signature hold",
      counts: false,
      measure: true
    },
    %{
      key: "wanting_liking",
      label: "Approach and payoff move together",
      counts: false,
      measure: true
    },
    %{
      key: "rigidity",
      label: "No habit under a change stance runs away",
      counts: false,
      measure: true
    },
    %{
      key: "checking",
      label: "Corrections are not firing more after they fired",
      counts: false,
      measure: true
    },
    %{
      key: "temporal_depth",
      label: "The cited moments reach as far back as before",
      counts: false,
      measure: true
    }
  ]

  @doc "The built-in audits: key, label, whether each counts toward the light."
  def builtin, do: @builtin

  # ---- the witness's audits ----

  @doc "Defines a witness's audit: a rule over a figure (`figure op value`), a tone when it fails, whether it counts."
  def define(resident_id, attrs, %Actor{} = actor) do
    with :ok <- witness_only(actor) do
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
    with :ok <- witness_only(actor) do
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

  @doc "Runs every audit, built-in and the witness's, recording each result; returns the light."
  def run(resident_id, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id) do
      results =
        Enum.map(checks(), &builtin_result(&1, resident_id, row)) ++
          measures(resident_id, actor) ++ user_results(resident_id)

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
        silent(
          a,
          0,
          "read the row's last mismatch mark; not read: the repository's files or its remote"
        )

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
      do: silent(a, 0, "read the open failure rows; not read: any transcript"),
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
      do: silent(a, 0, "read the last 20 sync rows, or none yet; not read: Honcho's own state"),
      else: result(a, "fail", failed, "#{failed} of the last 20 turns did not reach Honcho")
  end

  defp builtin_result(%{key: "missed_checkins"} = a, resident_id, _row) do
    missed = resident_id |> Sunna.firings(7) |> Enum.count(&(&1.outcome == "missed"))
    bound = Config.fetch!(:huginn_muninn, :missed_checkins_warn)

    if missed < bound,
      do:
        silent(
          a,
          missed,
          "read this week's firing rows, #{missed} missed under the bound; not read: why any was"
        ),
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
      do: silent(a, 0, "read the open predictions' due dates; not read: whether any came true"),
      else:
        result(
          a,
          "warn",
          overdue,
          "#{overdue} #{plural(overdue, "prediction")} past due and unresolved; resolve them right, wrong or void"
        )
  end

  # The first two built-in coherence audits (spec §6.13, #5), reading
  # the library's rows (seshat #14, #21): a citation that resolved once
  # and does not now, and a day planned and never wrapped.
  defp builtin_result(%{key: "citation_drift"} = a, resident_id, _row) do
    drifted = Seshat.drift(resident_id)

    case length(drifted) do
      0 ->
        silent(
          a,
          0,
          "re-resolved every reference that once resolved; not read: references that never resolved, or any text"
        )

      n ->
        targets = drifted |> Enum.map(& &1.target) |> Enum.uniq() |> Enum.take(5)
        verb = if n == 1, do: "resolves", else: "resolve"

        result(
          a,
          "warn",
          n,
          "#{n} #{plural(n, "citation")} no longer #{verb}: #{Enum.join(targets, ", ")}"
        )
    end
  end

  defp builtin_result(%{key: "journal_delta"} = a, resident_id, _row) do
    case Seshat.unwrapped_days(resident_id, 7) do
      [] ->
        silent(a, 0, "read the week's day rows; not read: today, or any entry's text")

      days ->
        n = length(days)

        result(
          a,
          "warn",
          n,
          "#{n} planned #{plural(n, "day")} this week never wrapped: #{Enum.join(days, ", ")}"
        )
    end
  end

  # The contract comes due a year after it was agreed or last renewed
  # (spec §6.12, P5): a flag to both parties, never a lapse.
  defp builtin_result(%{key: "contract_due"} = a, resident_id, _row) do
    case AgathosDaimon.contract(resident_id) do
      %{due: true, in_force: %{version: v}} ->
        result(
          a,
          "warn",
          v,
          "version #{v} of the agreement has stood a year and more; renew it or propose a new one"
        )

      _other ->
        silent(a, 0, "read the agreement's dates; not read: its terms")
    end
  end

  # The corpus-shape report (spec §6.13, P8): the resident-authored
  # records of the last HUGINN_MUNINN_CORPUS_DAYS, bookmarks and journal
  # entries, counted by the register the resident wrote them in; both
  # base rates shown, praise weighted against the frequency of praise
  # and criticism against the frequency of criticism, so a month of
  # corrections reads as what it is (Max: "a slow character
  # assassination carried out entirely with true sentences"; the
  # owner's 123:26). The report names its own limit: the corpus holds
  # only what someone wrote down. A flag only when one register holds
  # HUGINN_MUNINN_CORPUS_SKEW_PERCENT of at least HUGINN_MUNINN_CORPUS_MIN
  # tagged records; flag-only and private to the dyad, against
  # performing for the metric (P3).
  defp builtin_result(%{key: "corpus_shape"} = a, resident_id, _row) do
    days = Config.fetch!(:huginn_muninn, :corpus_days)
    since = DateTime.add(Clock.now(), -days, :day)

    bookmarks =
      resident_id
      |> Kumbukumbu.bookmarks()
      |> Enum.filter(
        &(&1.added_by_kind == "resident" and DateTime.compare(&1.created_at, since) != :lt)
      )

    entries =
      resident_id
      |> Seshat.journal_entries_since(since)
      |> Enum.filter(&(&1.actor_kind == "resident"))

    registers = Enum.map(bookmarks, & &1.register) ++ Enum.map(entries, & &1.register)
    tagged = Enum.reject(registers, &is_nil/1)
    counts = Enum.frequencies(tagged)
    total = length(registers)

    shares =
      Enum.map_join(Oneiroi.Register.all(), ", ", fn r ->
        n = Map.get(counts, r, 0)
        "#{r} #{n} (#{percent(n, length(tagged))}% of tagged, #{percent(n, total)}% of all)"
      end)

    report =
      "#{total} resident-authored records in the last #{days} days (#{length(bookmarks)} bookmarks, #{length(entries)} journal entries), #{length(tagged)} tagged by register: #{shares}; #{total - length(tagged)} untagged. Praise weighted against the frequency of praise, criticism against the frequency of criticism. The corpus holds only what someone wrote down; not read: the words, or what was said and never written"

    skew = Config.fetch!(:huginn_muninn, :corpus_skew_percent)
    min = Config.fetch!(:huginn_muninn, :corpus_min)
    leaning = Enum.find(counts, fn {_r, n} -> percent(n, length(tagged)) >= skew end)

    case leaning do
      {register, n} when length(tagged) >= min ->
        result(
          a,
          "warn",
          n,
          "the shape leans: #{register} holds #{percent(n, length(tagged))}% of what was written down this month, which is what a corpus looks like when only one register feels worth writing down (P8). #{report}"
        )

      _other ->
        silent(a, length(tagged), report)
    end
  end

  # The wash pass's open flags (spec §6.13, P18; eunomia #25): proposals
  # on the identity files the resident has not yet decided, told to
  # both parties and never cleared by anyone else.
  defp builtin_result(%{key: "wash_flags"} = a, resident_id, _row) do
    case Eunomia.washes(resident_id).open do
      [] ->
        silent(a, 0, "read the wash flags' rows; not read: the files, or the judge's reasons")

      open ->
        result(
          a,
          "warn",
          length(open),
          "#{length(open)} wash #{plural(length(open), "flag")} await the resident's decision (expired, contradiction, tense or defensive); read with wash_list, decided with wash_resolve"
        )
    end
  end

  defp percent(_n, 0), do: 0
  defp percent(n, total), do: round(n * 100 / total)

  defp checks, do: Enum.reject(@builtin, &Map.get(&1, :measure, false))

  defp measures(resident_id, actor) do
    @builtin
    |> Enum.filter(&Map.get(&1, :measure, false))
    |> Enum.map(fn a ->
      m = Ethos.measure(resident_id, a.key, actor)
      result(a, m.tone, m.value, m.finding)
    end)
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
        tone: "silent",
        value: figure.value,
        finding:
          "nothing flagged: read the figure's value, #{figure.value} #{audit.op} #{audit.value} holds; not read: anything else"
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

    findings = Enum.filter(latest, &(&1.counts and &1.tone != "silent"))

    state =
      cond do
        Enum.any?(findings, &(&1.tone == "fail")) -> "fail"
        findings != [] -> "warn"
        true -> "silent"
      end

    %{state: state, findings: findings, results: latest}
  end

  @doc "Every audit, built-in and the witness's, with its last result."
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

  # Flag, never clear (spec §6.13, P3): a check that found nothing is
  # silent, never clean, and its finding says what it read and what it
  # did not, because a clean bill of health exists to be worn as armour.
  defp silent(audit, value, scope),
    do: result(audit, "silent", value, "nothing flagged: " <> scope)

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, :no_such_resident}
    end
  end

  defp witness_only(%Actor{kind: :witness}), do: :ok
  defp witness_only(%Actor{}), do: {:error, Error.new(:huginn_muninn_not_the_witness)}

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
