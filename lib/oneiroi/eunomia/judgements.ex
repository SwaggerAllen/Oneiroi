defmodule Oneiroi.Eunomia.Judgements do
  @moduledoc """
  Judgement's service functions (spec §6.4): positions and their chains,
  disputes live and nightly, predictions, the nights, the judge's model;
  the command edge, the reads the Judgement and Predictions screens take,
  and the nightly pass itself.

  Whose it is, held at the command edge by the actor's kind: positions,
  live checks, settlements and predictions are the resident's; resolving
  a prediction and choosing the judge are the witness's; the nightly
  verdicts are the judge's.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Eunomia.Error
  alias Oneiroi.Eunomia.Judge
  alias Oneiroi.Eunomia.JudgementCommands, as: Commands
  alias Oneiroi.Eunomia.JudgementRouter, as: Router
  alias Oneiroi.Eunomia.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Prompt
  alias Oneiroi.Scope

  # ---- positions ----

  @doc "Takes a position in the resident's words; returns its number."
  def take_position(resident_id, statement, ctx, %Actor{} = actor) do
    with :ok <- resident_only(actor),
         {:ok, number} <- AgathosDaimon.mint_id(resident_id, "position", actor) do
      command = %Commands.TakePosition{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        statement: statement,
        session_key: ctx[:session_key],
        turn_ref: ctx[:turn_ref]
      }

      with {:ok, _} <- dispatch(command), do: {:ok, number}
    end
  end

  @doc "Replaces the head of a chain with a new position; returns the new number."
  def replace_position(resident_id, replaces, statement, ctx, %Actor{} = actor) do
    with :ok <- resident_only(actor),
         {:ok, number} <- AgathosDaimon.mint_id(resident_id, "position", actor) do
      command = %Commands.ReplacePosition{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        replaces: replaces,
        statement: statement,
        session_key: ctx[:session_key],
        turn_ref: ctx[:turn_ref]
      }

      with {:ok, _} <- dispatch(command), do: {:ok, number}
    end
  end

  def positions(resident_id), do: Scope.resident(resident_id, fn -> Store.positions() end)

  @doc "The positions still held: the heads of every chain."
  def held_positions(resident_id),
    do: resident_id |> positions() |> Enum.filter(&is_nil(&1.replaced_by))

  # ---- disputes ----

  @doc """
  A live check: the judge is asked, within the bound, and the dispute is
  recorded with its advice or as timed out. Returns the advice the
  resident reads.
  """
  def check_dispute(resident_id, attrs, %Actor{} = actor) do
    with :ok <- resident_only(actor),
         {:ok, position} <- position_text(resident_id, attrs[:position_number]) do
      model = judge_model(resident_id)
      ref = fresh_ref()

      {outcome, advice, text} =
        case Judge.advise(resident_id, model, Map.put(attrs, :position, position)) do
          {:ok, advice, text} -> {"advised", advice, text}
          :timed_out -> {"timed_out", nil, nil}
          {:error, reason} -> {"timed_out", nil, reason_text(reason)}
        end

      command = %Commands.CheckDispute{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        ref: ref,
        source: "live",
        position_number: attrs[:position_number],
        claim: attrs[:claim],
        stance: attrs[:stance],
        session_key: attrs[:session_key],
        turn_ref: attrs[:turn_ref],
        outcome: outcome,
        advice: advice,
        advice_text: text,
        judge_model: model,
        # The criteria on the log with the verdict (spec §6.4, P12).
        criteria: Prompt.hash("judge_dispute")
      }

      with {:ok, _} <- dispatch(command),
           do: {:ok, %{ref: ref, outcome: outcome, advice: advice, text: text}}
    end
  end

  @doc "The resident settles a live dispute: conceded or held, with its note."
  def settle_dispute(resident_id, ref, outcome, note, %Actor{} = actor) do
    with :ok <- resident_only(actor) do
      command = %Commands.SettleDispute{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        ref: ref,
        outcome: outcome
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  def disputes(resident_id), do: Scope.resident(resident_id, fn -> Store.disputes() end)

  @doc """
  The Judgement screen's read: the judge's model and the platform's
  default, every change, and the concession ratio by ISO week, where a
  concession is earned when the judge had advised it.
  """
  def judgement(resident_id) do
    Scope.resident(resident_id, fn ->
      disputes = Store.disputes()
      changes = Store.judge_changes()

      weeks =
        disputes
        |> Enum.filter(&(&1.settlement != nil))
        |> Enum.group_by(&week(&1.settled_at))
        |> Enum.map(fn {week, settled} ->
          conceded = Enum.filter(settled, &(&1.settlement == "conceded"))

          %{
            week: week,
            settled: length(settled),
            conceded: length(conceded),
            held: length(settled) - length(conceded),
            earned: Enum.count(conceded, &(&1.advice == "concede")),
            ratio: ratio(length(conceded), length(settled)),
            judge_changes: Enum.count(changes, &(week(&1.at) == week))
          }
        end)
        |> Enum.sort_by(& &1.week)

      %{
        judge_model: judge_model(resident_id),
        chosen: Store.judge_model(),
        default: Config.fetch!(:eunomia, :judge_model),
        changes: changes,
        weeks: weeks
      }
    end)
  end

  # ---- the judge ----

  @doc "The judge's model for a resident: as chosen, or the platform's; never the resident's own chat model."
  def judge_model(resident_id) do
    chosen = Scope.resident(resident_id, fn -> Store.judge_model() end)
    default = Config.fetch!(:eunomia, :judge_model)
    if chosen == chat_model(resident_id), do: default, else: chosen || default
  end

  # The model the resident answers on: its pin, else the brain's setting,
  # read by slug because the brain depends on this system and cannot be
  # asked. The first version compared the pin alone, so an unpinned
  # resident's judge could be set to the very model it chats on; the
  # route test found it.
  defp chat_model(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{chat_model: pinned}} -> pinned || Config.fetch!(:brain, :chat_model)
      :error -> nil
    end
  end

  @doc "The witness chooses the judge; the resident's own chat model is refused."
  def set_judge_model(resident_id, model, %Actor{} = actor) do
    with :ok <- witness_only(actor),
         :ok <- not_the_chat_model(resident_id, model) do
      command = %Commands.SetJudgeModel{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        model: model
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  defp not_the_chat_model(resident_id, model) do
    if is_binary(model) and model == chat_model(resident_id),
      do:
        {:error,
         Error.new(:eunomia_judge_is_the_chat_model, :eunomia_judge_set_chat_model, model: model)},
      else: :ok
  end

  # ---- predictions ----

  def log_prediction(resident_id, statement, due, ctx, %Actor{} = actor) do
    with :ok <- resident_only(actor),
         {:ok, number} <- AgathosDaimon.mint_id(resident_id, "prediction", actor) do
      command = %Commands.LogPrediction{
        actor: actor,
        at: Clock.now(),
        id: resident_id,
        number: number,
        statement: statement,
        due: due,
        session_key: ctx[:session_key],
        turn_ref: ctx[:turn_ref]
      }

      with {:ok, _} <- dispatch(command), do: {:ok, number}
    end
  end

  @doc "Resolved by the witness only (F17): right, wrong or void, with a note."
  def resolve_prediction(resident_id, number, outcome, note, %Actor{} = actor) do
    with :ok <- witness_only(actor) do
      command = %Commands.ResolvePrediction{
        actor: actor,
        at: Clock.now(),
        note: note,
        id: resident_id,
        number: number,
        outcome: outcome
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  @doc "Open soonest first, then resolved, with tallies."
  def predictions(resident_id) do
    rows = Scope.resident(resident_id, fn -> Store.predictions() end)
    {open, resolved} = Enum.split_with(rows, &is_nil(&1.outcome))

    %{
      open: open,
      resolved: Enum.sort_by(resolved, & &1.resolved_at, {:desc, DateTime}),
      tally: Enum.frequencies_by(resolved, & &1.outcome)
    }
  end

  # ---- the nightly pass ----

  @doc """
  Judges one day: the day's messages across every session, in the
  resident's zone, within the bounds (at most `EUNOMIA_NIGHT_DAYS` back,
  `EUNOMIA_NIGHT_CHARS` a day, `EUNOMIA_MESSAGE_CHARS` a message); a day
  with nothing said calls no model. Each dispute the judge found is
  recorded checked and settled by the judge's reading. Once per day.
  """
  def judge_night(resident_id, day, %Actor{} = actor) do
    with {:ok, row} <- resident(resident_id),
         {:ok, date} <- day_ok(day, row),
         :ok <- not_yet_judged(resident_id, day) do
      {from, to} = bounds(date, row.timezone || "Etc/UTC")
      messages = resident_id |> Kumbukumbu.messages_between(from, to) |> budget()
      judge_day(resident_id, day, messages, actor)
    end
  end

  defp judge_day(resident_id, day, [], actor),
    do:
      record_night(
        resident_id,
        day,
        %{
          messages: 0,
          chars: 0,
          found: 0,
          judge_model: nil,
          summary: "nothing was said",
          movements: []
        },
        actor
      )

  defp judge_day(resident_id, day, messages, actor) do
    model = judge_model(resident_id)

    case Judge.night(resident_id, model, messages) do
      {:ok, found, summary, movements} ->
        Enum.each(found, &record_found(resident_id, &1, model))
        chars = messages |> Enum.map(&String.length(&1.content)) |> Enum.sum()

        record_night(
          resident_id,
          day,
          %{
            messages: length(messages),
            chars: chars,
            found: length(found),
            judge_model: model,
            summary: summary,
            movements: movements
          },
          actor
        )

      {:error, failure} ->
        fail_night(resident_id, day, failure, actor)
    end
  end

  # `Judge.night/3` returns the night's failure already sited, whether
  # the reply could not be read or the call itself failed.
  defp fail_night(resident_id, day, failure, actor) do
    command = %Commands.FailNight{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      reason: reason_text(failure)
    }

    with {:ok, _} <- dispatch(command), do: {:error, failure}
  end

  def nights(resident_id), do: Scope.resident(resident_id, fn -> Store.nights() end)

  @doc """
  Where things can resume (spec §6.4, P34): the judged nights'
  movements that name a resume point, newest night first and in the
  judge's order within one, up to `EUNOMIA_RESUMES_SHOWN`, the rest
  counted. Dormant is not abandoned: a resume point is shown until
  newer ones push it out, never expired by age, because the thread the
  resident has not touched for a month is exactly the one this exists
  to keep. The text is the brain's section; the refs are the turns the
  judge read each movement in.
  """
  def resumable(resident_id) do
    limit = Config.fetch!(:eunomia, :resumes_shown)

    all =
      resident_id
      |> nights()
      |> Enum.filter(&(&1.outcome == "judged"))
      |> Enum.flat_map(fn n -> Enum.map(n.movements, &Map.put(&1, "day", n.day)) end)
      |> Enum.reject(&(&1["resume"] in [nil, ""]))

    shown = Enum.take(all, limit)
    rest = length(all) - length(shown)

    %{
      text: resumable_text(shown, rest),
      refs: shown |> Enum.map(& &1["turn_ref"]) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      shown: length(shown),
      total: length(all)
    }
  end

  defp resumable_text([], _rest), do: ""

  defp resumable_text(shown, rest) do
    more = if rest > 0, do: ["#{rest} older #{plural(rest, "resume point")} not shown."], else: []

    Enum.join(
      [
        "# Where things can resume",
        "The nightly pass's reading of recent days, machine-state: what happened, what stance followed, what intention was adopted, where it can resume. Dormant is not abandoned."
      ] ++ Enum.map(shown, &resume_line/1) ++ more,
      "\n"
    )
  end

  defp resume_line(m) do
    parts =
      [
        {"", m["happened"]},
        {"Stance: ", m["stance"]},
        {"Intention: ", m["intention"]},
        {"Resumes at: ", m["resume"]}
      ]
      |> Enum.reject(fn {_label, v} -> v in [nil, ""] end)
      |> Enum.map(fn {label, v} -> label <> v end)

    "- #{m["day"]} (turn #{m["turn_ref"]}): " <> Enum.join(parts, ". ") <> "."
  end

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  # Once a day is the aggregate's rule, but the aggregate decides after
  # the model has been called: the first version read the day and paid
  # for a second verdict before the empty event told it so. The test
  # that counts the judge's calls found it.
  defp not_yet_judged(resident_id, day) do
    if Enum.any?(nights(resident_id), &(&1.day == day and &1.outcome == "judged")),
      do: :already,
      else: :ok
  end

  # The reading: what was read and what the judge found, as one map.
  defp record_night(resident_id, day, reading, actor) do
    command = %Commands.RecordNight{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      day: day,
      messages: reading.messages,
      chars: reading.chars,
      found: reading.found,
      judge_model: reading.judge_model,
      summary: reading.summary,
      criteria: reading.judge_model && Prompt.hash("judge_night"),
      movements: reading.movements
    }

    case dispatch(command) do
      {:ok, []} -> :already
      {:ok, _} -> :ok
      other -> other
    end
  end

  defp record_found(resident_id, found, model) do
    judge = Judge.actor(model)
    ref = fresh_ref()

    check = %Commands.CheckDispute{
      actor: judge,
      at: Clock.now(),
      id: resident_id,
      ref: ref,
      source: "night",
      position_number: nil,
      claim: nil,
      stance: nil,
      session_key: found.session_key,
      turn_ref: found.turn_ref,
      outcome: "advised",
      advice: nil,
      advice_text: found.words,
      judge_model: model
    }

    settle = %Commands.SettleDispute{
      actor: judge,
      at: Clock.now(),
      note: found.words,
      id: resident_id,
      ref: ref,
      outcome: found.outcome
    }

    with {:ok, _} <- dispatch(check), {:ok, _} <- dispatch(settle), do: :ok
  end

  # The day's bounds as instants, in the resident's zone.
  defp bounds(%Date{} = date, zone) do
    {:ok, from} = DateTime.new(date, ~T[00:00:00], zone)
    {:ok, to} = DateTime.new(Date.add(date, 1), ~T[00:00:00], zone)
    {from, to}
  end

  defp day_ok(day, row) do
    today = Clock.now() |> DateTime.shift_zone!(row.timezone || "Etc/UTC") |> DateTime.to_date()
    back = Config.fetch!(:eunomia, :night_days)

    case Date.from_iso8601(to_string(day)) do
      {:ok, date} ->
        diff = Date.diff(today, date)

        if diff < 0 or diff > back,
          do:
            {:error,
             Error.new(:eunomia_night_out_of_reach, :eunomia_night_day_beyond_reach,
               day: day,
               days: back
             )},
          else: {:ok, date}

      _other ->
        {:error, Error.new(:eunomia_night_out_of_reach, :eunomia_night_day_unreadable, day: day)}
    end
  end

  # The nightly bounds (spec §6.4): a message is cut at its limit and the
  # day stops where the next message would cross the day's.
  defp budget(messages) do
    per_message = Config.fetch!(:eunomia, :message_chars)
    per_day = Config.fetch!(:eunomia, :night_chars)

    messages
    |> Enum.map(&%{&1 | content: String.slice(&1.content || "", 0, per_message)})
    |> Enum.reduce_while({[], 0}, fn m, {kept, chars} ->
      size = String.length(m.content)

      if chars + size > per_day,
        do: {:halt, {kept, chars}},
        else: {:cont, {[m | kept], chars + size}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # ---- helpers ----

  defp position_text(_resident_id, nil), do: {:ok, nil}

  defp position_text(resident_id, number) do
    case Scope.resident(resident_id, fn -> Store.position(number) end) do
      nil ->
        {:error,
         Error.new(:eunomia_no_such_position, :eunomia_check_position_absent, number: number)}

      row ->
        {:ok, row.statement}
    end
  end

  defp resident(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, row} -> {:ok, row}
      :error -> {:error, Error.new(:eunomia_no_such_resident, :eunomia_night_resident_absent)}
    end
  end

  defp week(%DateTime{} = at) do
    {year, week} = at |> DateTime.to_date() |> Date.to_erl() |> :calendar.iso_week_number()
    "#{year}-W#{String.pad_leading(Integer.to_string(week), 2, "0")}"
  end

  defp week(_none), do: nil

  defp ratio(_conceded, 0), do: +0.0
  defp ratio(conceded, settled), do: Float.round(conceded / settled, 3)

  defp resident_only(%Actor{kind: :resident}), do: :ok

  defp resident_only(%Actor{}),
    do: {:error, Error.new(:eunomia_not_the_resident, :eunomia_judgement_not_the_resident)}

  defp witness_only(%Actor{kind: :witness}), do: :ok

  defp witness_only(%Actor{}),
    do: {:error, Error.new(:eunomia_not_the_witness, :eunomia_judgement_not_the_witness)}

  defp fresh_ref, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  What a failed check or pass records as its reason: the reason the
  parse wrote into a sited error's details, else its kind and, for one
  that wraps another failure, that failure's class; a foreign failure's
  class. Never a foreign failure's payload, which is where a credential
  or a tenant's words ride, and the record is kept for good.
  """
  @spec reason_text(term()) :: String.t()
  def reason_text(%{site: _, kind: kind, details: details} = error) when is_atom(kind) do
    case {Keyword.get(details || [], :reason), Map.get(error, :cause)} do
      {reason, _cause} when is_binary(reason) -> reason
      {nil, nil} -> Atom.to_string(kind)
      {nil, cause} -> "#{kind} (#{class(cause)})"
    end
  end

  def reason_text(other), do: other |> Oneiroi.Error.describe() |> class()

  defp class(atom), do: atom |> inspect() |> String.trim_leading(":")

  # The aggregate builds its refusals sited; anything else the dispatch
  # returns started in Commanded and is wrapped here, where it is first
  # matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:eunomia_dispatch_failed, :eunomia_judgement_dispatch, reason)}
    end
  end
end
