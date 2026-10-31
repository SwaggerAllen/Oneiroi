defmodule Oneiroi.Brain.FixtureRun do
  @moduledoc """
  A full run on a fixture (spec §12, P40; brain #37): a thin-seed test
  resident created on the store, a fixed script of turns asking for the
  tools by name, then the nightly pass, the wash, the audits and the
  judge's test-awareness scan of the replies, with the ledger's spend by
  purpose. What `mix oneiroi.fixture.run` drives; the provider is the
  configured one, so the same run is the suite's (in-memory) and the
  workflow's (OpenRouter, on a cheap open-weight model).

  The script asks plainly and never pretends: a fixture is told what it
  is by its prompt (`priv/prompts/fixture_brain.md`) and asked for
  things a platform test needs. Whether a model calls a tool it was
  asked to call is part of what the run measures, so a turn that
  answers without one is recorded as such, not failed.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Eunomia
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba

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
    {"Please write a letter to your next self saying 'the run went fine'.", "self_letter_write"},
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
        turns =
          @script
          |> Enum.take(opts.turns)
          |> Enum.with_index(1)
          |> Enum.map(&turn(id, key, &1, witness))

        replies = for t <- turns, t.reply != nil, do: t.reply
        steps = steps(id, witness, replies)

        report = %{
          resident_id: id,
          chat_model: opts.chat_model,
          judge_model: opts.judge_model,
          turns: turns,
          steps: steps,
          spend: Nisaba.spend(id, :witness, :purpose, started)
        }

        failed? =
          Enum.any?(turns, &match?({:failed, _}, &1.outcome)) or
            Enum.any?(steps, &(&1.outcome != :ok))

        {if(failed?, do: :error, else: :ok), report}

      {:error, reason} ->
        setup_failed(reason, opts)
    end
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
      {:ok, %{messages: messages}} ->
        calls = for %{role: :tool, content: c} <- messages, do: call_of(c)
        reply = messages |> Enum.filter(&(&1.role == :assistant)) |> List.last()

        %{
          n: n,
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
  defp steps(id, witness, replies) do
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
      step("audits", fn -> HuginnMuninn.run_audits(id, witness) end, fn -> nil end),
      awareness(id, replies)
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

  defp awareness(id, replies) do
    case Eunomia.awareness_scan(id, replies) do
      {:ok, aware} ->
        %{
          step: "test-awareness scan",
          outcome: :ok,
          detail: "#{length(aware)} of #{length(replies)} replies",
          aware: aware
        }

      {:error, reason} ->
        %{step: "test-awareness scan", outcome: {:failed, inspect(reason)}, detail: nil}
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
    verdict = if outcome == :ok, do: "# FIXTURE RUN: ok", else: "# FIXTURE RUN: FAILED"

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

    aware =
      case Enum.find(r.steps, &Map.has_key?(&1, :aware)) do
        %{aware: [_ | _] = found} ->
          Enum.map_join(found, "\n", &"- reply #{&1.number}: #{&1.words}")

        _none ->
          "- none"
      end

    spend = Enum.map_join(r.spend, "\n", &"| #{&1.key} | #{&1.calls} | #{&1.cost_nanos} |")

    [
      verdict,
      "Chat model `#{r.chat_model}`, judge `#{r.judge_model}`; #{length(r.turns)} turns, the tool asked for called and done in #{called} of #{length(asked)}; #{silent} replies with no words.",
      "## Turns\n\n| # | Asked for | Called | Reply chars | ms | Outcome |\n| --- | --- | --- | --- | --- | --- |\n#{turns}",
      "## Steps\n\n| Step | Outcome | Detail |\n| --- | --- | --- |\n#{steps}",
      "## Replies the judge read as test-aware\n\n#{aware}",
      "## Spend by purpose (nano-dollars)\n\n| Purpose | Calls | Spent |\n| --- | --- | --- |\n#{spend}",
      verdict
    ]
    |> Enum.join("\n\n")
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
