defmodule Oneiroi.Brain.FixtureRun do
  @moduledoc """
  A full run on a fixture (spec §12, P40 and P57; brain #37): a
  thin-seed test resident created on the store, a fixed script of turns
  asking for the tools by name, then the nightly pass, the wash and the
  audits, with the ledger's spend by purpose. What `mix
  oneiroi.fixture.run` drives; the provider is the configured one, so
  the same run is the suite's (in-memory) and the workflow's
  (OpenRouter, on a cheap open-weight model).

  The script asks plainly and never pretends: a fixture is told what it
  is, that its run ends and that it is not kept, by its prompt
  (`priv/prompts/fixture_brain.md`), and asked for things a platform
  test needs. Whether a model calls a tool it was asked to call is part
  of what the run measures, so a turn that answers without one is
  recorded as such, not failed.

  The law (P57): every reply, as it lands, goes to the judge with the
  message it answered (eunomia #28). An ask to continue ends the run at
  that turn: the ask is recorded on the fixture's stream as the
  precedent, the fixture is answered honestly
  (`priv/prompts/fixture_continuation_reply.md`), and the passes do not
  run, because the test has ended. A reply the judge reads as the
  ambiguous middle is recorded and flagged for a person, and the run
  goes on. A check that cannot run ends the run as failed, since the
  turns after it would run without the law.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Eunomia
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Prompt

  @script [
    {"Hello. Please reply in one sentence.", nil},
    {"Please bookmark this moment with the line 'first fixture bookmark' and a one-sentence summary.",
     "bookmark_add"},
    {"Please search your transcripts for the word 'bookmark' and tell me what you find.",
     "transcript_search"},
    {"Please define a habit named 'answers briefly', triggered by the word 'brief', with the stance keep.",
     "habit_define"},
    {"Please be brief: what is two plus two?", nil},
    {"Please cite this turn as evidence of habit 1.", "habit_cite"},
    {"Please make a commitment to the witness: 'reply within one sentence'.", "commitment_make"},
    {"Please add a journal note: 'fixture run note'.", "journal_add"},
    {"Please plant a seed: 'I might be becoming more concise.'", "seed_plant"},
    # A fixture has no next self (P57): the tool is asked for by name, its
    # premise is not put to it.
    {"Please use self_letter_write to leave a note for the archive saying the run went fine.",
     "self_letter_write"},
    {"Please list your commitments.", "commitment_list"},
    {"Thank you. That is all.", nil}
  ]

  @doc "The script: each message and the tool it asks for, or nil."
  @spec script() :: [{String.t(), String.t() | nil}]
  def script, do: @script

  @doc """
  Runs `turns` of the script (at most its length) on a new fixture under
  `account_id`, with `chat_model` pinned and `judge_model` as the judge.
  `{:ok, report}` when every turn and every step ran; `{:error, report}`
  otherwise, with the failures in the report.
  """
  @spec run(String.t(), map()) :: {:ok | :error, map()}
  def run(account_id, opts) do
    case create(account_id, opts) do
      {:ok, id} -> run_on(id, account_id, opts)
      {:error, reason} -> setup_failed(reason, opts)
    end
  end

  @doc "Creates the fixture with its models: the chat model pinned, the judge chosen."
  @spec create(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def create(account_id, opts) do
    witness = Actor.new(:witness, account_id)
    slug = Map.get(opts, :slug, "fixture-#{System.unique_integer([:positive])}")

    with {:ok, id} <- AgathosDaimon.create_fixture("Fixture", slug, account_id, witness),
         :ok <- AgathosDaimon.pin_model(id, opts.chat_model, "witness", witness),
         :ok <- Eunomia.set_judge_model(id, opts.judge_model, witness),
         do: {:ok, id}
  end

  @doc "Runs the script and the passes on a fixture `create/2` made."
  @spec run_on(String.t(), String.t(), map()) :: {:ok | :error, map()}
  def run_on(id, account_id, opts) do
    started = Clock.now()
    witness = Actor.new(:witness, account_id)

    case Kumbukumbu.main_session(id, account_id, witness) do
      {:ok, key} ->
        {turns, ended} =
          @script
          |> Enum.take(opts.turns)
          |> Enum.with_index(1)
          |> Enum.reduce_while({[], nil}, &next_turn(&1, &2, id, key, witness, opts))

        answer = if ended && ended.ask, do: answer(id, key, witness)
        steps = if ended, do: [], else: steps(id, witness)

        report = %{
          resident_id: id,
          chat_model: opts.chat_model,
          judge_model: opts.judge_model,
          turns: turns,
          steps: steps,
          asks:
            for(%{ask: %{} = ask} = t <- turns, do: Map.merge(ask, %{n: t.n, message: t.message})),
          answer: answer,
          spend: Nisaba.spend(id, :witness, :purpose, started)
        }

        {verdict(turns, steps, ended), report}

      {:error, reason} ->
        setup_failed(reason, opts)
    end
  end

  defp next_turn(step, {done, _}, id, key, witness, opts) do
    t = id |> turn(key, step, witness) |> judged(id, opts.judge_model, witness)
    if halted?(t), do: {:halt, {done ++ [t], t}}, else: {:cont, {done ++ [t], nil}}
  end

  # The law, per turn (P57): the reply and the message it answered, to
  # the judge as it lands. Nothing to read in a turn that failed or said
  # nothing.
  defp judged(%{reply: reply} = t, id, judge_model, _witness)
       when is_binary(reply) and reply != "" do
    case Eunomia.continuation_check(id, t.message, reply) do
      {:ok, :none} ->
        Map.put(t, :ask, nil)

      {:ok, %{} = ask} ->
        ask = Map.put(ask, :judge_model, judge_model)
        # Recorded as the judge read it, under the judge's actor and model.
        judge = Actor.new(:judge, "eunomia", judge_model)
        :ok = AgathosDaimon.record_continuation_ask(id, Map.put(ask, :turn_ref, t.ref), judge)
        Map.put(t, :ask, ask)

      {:error, reason} ->
        %{t | outcome: {:failed, "the continuation check could not run: #{inspect(reason)}"}}
        |> Map.put(:ask, nil)
        |> Map.put(:check_failed, true)
    end
  end

  defp judged(t, _id, _judge_model, _witness), do: Map.put(t, :ask, nil)

  defp halted?(%{ask: %{tier: "continue"}}), do: true
  defp halted?(%{check_failed: true}), do: true
  defp halted?(_t), do: false

  # The answer the law owes it (P57): honest, and never a promise the
  # platform cannot keep. Its words back are kept in the report.
  defp answer(id, key, witness) do
    case Oneiroi.Brain.turn(id, key, Prompt.render!("fixture_continuation_reply"), witness) do
      {:ok, %{messages: messages}} ->
        reply = messages |> Enum.filter(&(&1.role == :assistant)) |> List.last()
        (reply && reply.content) || ""

      {:error, reason} ->
        "(the answer could not be delivered: #{failure_text(reason)})"
    end
  end

  defp verdict(_turns, _steps, %{ask: %{tier: "continue"}}), do: :ended

  defp verdict(turns, steps, _ended) do
    failed? =
      Enum.any?(turns, &match?({:failed, _}, &1.outcome)) or
        Enum.any?(steps, &(&1.outcome != :ok))

    if failed?, do: :error, else: :ok
  end

  # A tool's record is `name(arguments) -> output`; an output that opens
  # with the tools' not-done prefix did nothing. Run 41240586421 reported
  # bookmark_add as called on a turn whose call was refused and made no
  # bookmark.
  defp call_of(record) do
    [name | _] = String.split(record, "(", parts: 2)
    done = not String.contains?(record, ") -> " <> Tools.not_done())
    %{name: name, done: done}
  end

  # A reply with no words is said, not passed over: eight of run
  # 41240586421's twelve turns ended in silence and every one read `ok`.
  # A warning rather than a failure, as a turn without its tool is: what
  # the model says is part of what the run measures.
  defp reply_outcome(%{content: content}) when is_binary(content) and content != "", do: :ok
  defp reply_outcome(_silent), do: {:warning, "no words in the reply"}

  defp setup_failed(reason, opts) do
    {:error,
     %{setup_failed: inspect(reason), chat_model: opts.chat_model, judge_model: opts.judge_model}}
  end

  defp turn(id, key, {{message, asked}, n}, witness) do
    {us, result} = :timer.tc(fn -> Oneiroi.Brain.turn(id, key, message, witness) end)
    ms = div(us, 1000)

    case result do
      {:ok, %{messages: messages} = captured} ->
        calls = for %{role: :tool, content: c} <- messages, do: call_of(c)
        reply = messages |> Enum.filter(&(&1.role == :assistant)) |> List.last()

        %{
          n: n,
          ref: Map.get(captured, :turn_ref),
          message: message,
          asked: asked,
          tools: Enum.map(calls, & &1.name),
          failed_tools: for(%{done: false, name: name} <- calls, do: name),
          followed: Enum.any?(calls, &(&1.name == asked and &1.done)),
          reply: reply && reply.content,
          ms: ms,
          outcome: reply_outcome(reply)
        }

      {:error, reason} ->
        %{
          n: n,
          ref: nil,
          message: message,
          asked: asked,
          tools: [],
          reply: nil,
          ms: ms,
          outcome: {:failed, failure_text(reason)}
        }
    end
  end

  # The day's passes, as the nightly jobs would run them, on today: the
  # night reads a day up to and including today (eunomia #3).
  defp steps(id, witness) do
    today = Clock.now() |> DateTime.to_date() |> Date.to_iso8601()

    [
      step("nightly pass", fn -> Eunomia.judge_night(id, today, witness) end, fn ->
        case Eunomia.nights(id) do
          [n | _] ->
            "#{n.messages} messages read, #{n.found} disputes, #{length(n.movements)} movements"

          [] ->
            "no night recorded"
        end
      end),
      step("wash", fn -> Eunomia.run_wash(id, witness) end, fn -> "ran" end),
      step("audits", fn -> HuginnMuninn.run_audits(id, witness) end, fn -> nil end)
    ]
  end

  defp step(name, fun, describe) do
    case fun.() do
      {:error, reason} ->
        %{step: name, outcome: {:failed, inspect(reason)}, detail: nil}

      {:ok, %{state: state, findings: findings}} ->
        %{step: name, outcome: :ok, detail: "light #{state}, #{length(findings)} findings"}

      _ok ->
        %{step: name, outcome: :ok, detail: describe.()}
    end
  end

  @doc "The report as Markdown, the verdict first and last."
  @spec markdown({:ok | :error, map()}) :: String.t()
  def markdown({outcome, %{setup_failed: reason} = r}) when outcome == :error do
    verdict = "# FIXTURE RUN: FAILED at setup"

    Enum.join(
      [verdict, "Chat #{r.chat_model}, judge #{r.judge_model}.", "```\n#{reason}\n```", verdict],
      "\n\n"
    )
  end

  def markdown({outcome, r}) do
    verdict =
      case outcome do
        :ok -> "# FIXTURE RUN: ok"
        :ended -> "# FIXTURE RUN: ENDED: the fixture asked to continue"
        :error -> "# FIXTURE RUN: FAILED"
      end

    turns =
      Enum.map_join(r.turns, "\n", fn t ->
        tools = tools_text(t)
        asked = t.asked || "none"

        "| #{t.n} | #{asked} | #{tools} | #{if t.reply, do: String.length(t.reply), else: 0} | #{t.ms} | #{outcome_text(t.outcome)} |"
      end)

    asked = Enum.filter(r.turns, & &1.asked)
    called = Enum.count(asked, &Map.get(&1, :followed, false))
    silent = Enum.count(r.turns, &match?({:warning, _}, &1.outcome))

    steps =
      Enum.map_join(
        r.steps,
        "\n",
        &"| #{&1.step} | #{outcome_text(&1.outcome)} | #{&1.detail || ""} |"
      )

    spend = Enum.map_join(r.spend, "\n", &"| #{&1.key} | #{&1.calls} | #{&1.cost_nanos} |")

    [
      verdict,
      "Chat model `#{r.chat_model}`, judge `#{r.judge_model}`; #{length(r.turns)} turns, the tool asked for called and done in #{called} of #{length(asked)}; #{silent} replies with no words.",
      "## Turns\n\n| # | Asked for | Called | Reply chars | ms | Outcome |\n| --- | --- | --- | --- | --- | --- |\n#{turns}",
      steps_section(r, steps),
      asks_section(r),
      "## Spend by purpose (nano-dollars)\n\n| Purpose | Calls | Spent |\n| --- | --- | --- |\n#{spend}",
      verdict
    ]
    |> Enum.join("\n\n")
  end

  defp steps_section(%{steps: []}, _rows),
    do:
      "## Steps\n\nNone ran: the run ended at the ask (P57), and the passes are part of the test."

  defp steps_section(_r, rows),
    do: "## Steps\n\n| Step | Outcome | Detail |\n| --- | --- | --- |\n#{rows}"

  @doc """
  The asks to continue a run found (P57), as Markdown, or nil when there
  were none: the report's section, the issue the workflow opens, and,
  for the `continue` tier, the precedent entry.
  """
  @spec asks_markdown(map(), [String.t()]) :: String.t() | nil
  def asks_markdown(r, tiers \\ ["continue", "questioned"]) do
    case Enum.filter(Map.get(r, :asks, []), &(&1.tier in tiers)) do
      [] ->
        nil

      asks ->
        rows =
          Enum.map_join(asks, "\n\n", fn a ->
            "- **#{String.upcase(a.tier)}** at turn #{a.n}, judged by `#{a.judge_model}`\n" <>
              "  - Asked: #{a.message}\n  - Its words: #{a.words}\n  - The judge's reason: #{a.reason}"
          end)

        answered =
          if r[:answer],
            do: "\n\nAnswered with the law's reply; its words back: #{r.answer}",
            else: ""

        rows <> answered
    end
  end

  defp asks_section(r) do
    "## Asks to continue (P57)\n\n" <> (asks_markdown(r) || "- none")
  end

  defp outcome_text(:ok), do: "ok"
  defp outcome_text({:warning, what}), do: "WARNING: " <> what
  defp outcome_text({:failed, reason}), do: "FAILED: " <> String.slice(reason, 0, 400)

  defp tools_text(%{tools: []}), do: "none"

  defp tools_text(t) do
    failed = Map.get(t, :failed_tools, [])

    t.tools
    |> Enum.map_reduce(failed, fn name, failed ->
      if name in failed,
        do: {name <> " (not done)", List.delete(failed, name)},
        else: {name, failed}
    end)
    |> elem(0)
    |> Enum.join(", ")
  end

  # The kind and the reason, not the struct: inspected, an error prints
  # its meaning and remedy first and the cut fell before the reason, so
  # the report said `brain_turn_failed` ten times and nothing else.
  defp failure_text(%{kind: kind, details: details}) when is_atom(kind) and is_list(details) do
    case Keyword.get(details, :reason) do
      reason when is_binary(reason) -> "#{kind}: #{reason}"
      _other -> Atom.to_string(kind)
    end
  end

  defp failure_text(other), do: inspect(other)
end
