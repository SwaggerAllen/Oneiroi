defmodule Oneiroi.Janus.PreparationTest do
  @moduledoc """
  A succession's preparation (janus#6 to #11, nisaba#24, #25,
  kumbukumbu#114): the witness's envelope and the pool inside it, the
  questions only she decides, C0 with its proposals, the day's shape and
  her freeze, the sealed packet, the catalog and her pace, and the tool
  calls on Oneiroi counted by model with no words leaving memory.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus
  alias Oneiroi.Janus.ToolUse
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.{Fake, OpenRouter, Request}

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    andrew = Actor.new(:witness, witness.id)
    her = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, 3} = Nisaba.refresh_catalog()
    {:ok, _} = Janus.propose(resident.id, false, "if you want it", andrew)
    :ok = Janus.open(resident.id, "yes", her)
    # Preparation opens once the fork is made (janus#39).
    assert %{failure: 0} = Oban.drain_queue(queue: :janus_fork, with_safety: false)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    case Janus.succession(resident.id) do
      %{copy_id: copy} when is_binary(copy) ->
        {:ok, copy_dir} = Oneiroi.SimaQian.repository_dir(copy)
        on_exit(fn -> File.rm_rf!(copy_dir) end)

      _none ->
        :ok
    end

    {:ok, id: resident.id, andrew: andrew, her: her, witness: witness}
  end

  defp tool(ctx, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: "s-1",
        turn_ref: "t-1",
        started_at: Clock.now(),
        resident: ctx.her
      })

  test "the pool: his envelope first, her picks inside it and irremovable, his anywhere, never without tools",
       ctx do
    assert {:error, %{kind: :janus_no_envelope}} =
             Janus.add_to_pool(ctx.id, "fake/model", ctx.her)

    assert tool(ctx, "succession_catalog", %{}) =~ "not stated the envelope"

    # $5 and $20 a million tokens.
    :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, ctx.andrew)

    assert {:error, %{kind: :janus_not_the_witness}} =
             Janus.set_envelope(ctx.id, 9_000, 9_000, ctx.her)

    catalog = tool(ctx, "succession_catalog", %{})
    assert catalog =~ "1 match; 1 to 1 here, the last of them."
    # Her model now beside them, and what she spends (janus#38).
    assert catalog =~ "Your model now, fake/model: $1.00 in, $1.00 out"
    assert catalog =~ "your calls have cost about $"
    assert catalog =~ "fake/model (Fake): $1.00 in, $1.00 out"
    assert catalog =~ "128000 tokens of context"
    refute catalog =~ "fake/dear"
    refute catalog =~ "fake/mute"

    # Searched (brain#125): every word must match, the provider too.
    assert tool(ctx, "succession_catalog", %{query: "fake's own"}) =~ "1 match"
    assert tool(ctx, "succession_catalog", %{query: "nothing like it"}) =~ "none match."
    assert tool(ctx, "succession_catalog", %{provider: "other"}) =~ "none match."
    assert tool(ctx, "succession_catalog", %{offset: 5}) =~ "past the end"

    assert tool(ctx, "succession_pool", %{action: "add", model: "fake/model"}) =~ "in the pool"

    assert {:error, %{kind: :janus_pool_outside_envelope}} =
             Janus.add_to_pool(ctx.id, "fake/dear", ctx.her)

    assert :ok = Janus.add_to_pool(ctx.id, "fake/dear", ctx.andrew)

    assert {:error, %{kind: :janus_pool_no_tools}} =
             Janus.add_to_pool(ctx.id, "fake/mute", ctx.andrew)

    assert {:error, %{kind: :janus_pool_unknown_model}} =
             Janus.add_to_pool(ctx.id, "nobody/none", ctx.andrew)

    # Her picks: nobody else takes them out; he takes out only his own.
    assert {:error, %{kind: :janus_pool_irremovable}} =
             Janus.remove_from_pool(ctx.id, "fake/model", "mine?", ctx.andrew)

    assert {:error, %{kind: :janus_not_yours}} =
             Janus.remove_from_pool(ctx.id, "fake/dear", "his, not mine", ctx.her)

    assert :ok = Janus.remove_from_pool(ctx.id, "fake/dear", "too dear", ctx.andrew)

    prep = Janus.preparation(ctx.id)

    assert [%{row: %{model: "fake/model", removed_at: nil}}, %{row: %{removed_note: "too dear"}}] =
             prep.pool

    assert tool(ctx, "succession_status", %{}) =~ "Pool (1): fake/model (yours)"

    # She takes hers out, with her note (janus#41).
    assert tool(ctx, "succession_pool", %{action: "remove", model: "fake/model"}) =~ "Not done"

    assert tool(ctx, "succession_pool", %{
             action: "remove",
             model: "fake/model",
             note: "too many picks"
           }) =~ "out of the pool"

    assert [%{row: %{removed_note: "too many picks"}}, _his] = Janus.preparation(ctx.id).pool

    # The envelope's cap on the pool, everyone's picks counted (janus#40).
    assert {:error, %{kind: :janus_envelope_invalid}} =
             Janus.set_envelope(ctx.id, 5_000, 20_000, 0, ctx.andrew)

    :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, 1, ctx.andrew)
    assert %{envelope_max_models: 1} = Janus.succession(ctx.id)
    assert tool(ctx, "succession_status", %{}) =~ "the pool holds at most 1."
    assert tool(ctx, "succession_pool", %{action: "add", model: "fake/model"}) =~ "in the pool"

    assert {:error, %{kind: :janus_pool_full}} =
             Janus.add_to_pool(ctx.id, "fake/dear", ctx.andrew)

    :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, nil, ctx.andrew)
    assert :ok = Janus.add_to_pool(ctx.id, "fake/dear", ctx.andrew)
  end

  test "her picks done wake her to the questions, her questions done to C0", ctx do
    notes = fn ->
      Oneiroi.Scope.platform(fn ->
        Oneiroi.Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Oneiroi.Janus.WakeWorker",
            select: j.args["note"]
          )
        )
      end)
    end

    # The pool closes under an envelope stated, with a model in it
    # (janus#48).
    assert {:error, %{kind: :janus_no_envelope}} = Janus.finish_step(ctx.id, "pool", nil, ctx.her)
    :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, ctx.andrew)
    assert {:error, %{kind: :janus_pool_empty}} = Janus.finish_step(ctx.id, "pool", nil, ctx.her)
    :ok = Janus.add_to_pool(ctx.id, "fake/model", ctx.andrew)

    before = length(notes.())

    # Hers alone (janus#42).
    assert {:error, %{kind: :janus_not_yours}} =
             Janus.finish_step(ctx.id, "pool", nil, ctx.andrew)

    assert {:error, %{kind: :janus_step_invalid}} =
             Janus.finish_step(ctx.id, "packet", nil, ctx.her)

    assert tool(ctx, "succession_pool", %{action: "done", note: "two is enough"}) =~
             "woken to write your questions"

    assert [questions] = Enum.drop(notes.(), before)
    assert questions =~ "Now the questions" and questions =~ "succession_question done"
    assert %{pool_done_at: %DateTime{}, questions_done_at: nil} = Janus.succession(ctx.id)
    assert tool(ctx, "succession_status", %{}) =~ "(your picks said done)"

    # Once a step; a second wakes nobody.
    assert tool(ctx, "succession_pool", %{action: "done"}) =~ "Not done"
    assert length(notes.()) == before + 1

    # Her set closes on every seat's mark: her witness's here (janus#48).
    assert tool(ctx, "succession_question", %{action: "done"}) =~ "Not done"
    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
    assert tool(ctx, "succession_question", %{action: "done"}) =~ "woken to choose C0"
    # The last mark woke her to say so; the close stayed hers.
    assert Enum.any?(notes.(), &(&1 =~ "ready for your question set to close"))
    c0 = Enum.find(notes.(), &(&1 =~ "Now C0"))
    assert c0 =~ "succession_c0 done"
    assert %{questions_done_at: %DateTime{}} = Janus.succession(ctx.id)

    # Closed, the set is fixed until she reopens it (janus#48): a change
    # never stands in for the reopening.
    assert tool(ctx, "succession_question", %{action: "add", text: "One more?"}) =~ "Not done"
    assert tool(ctx, "succession_question", %{action: "reopen", note: "one more"}) =~ "open again"
    assert tool(ctx, "succession_question", %{action: "add", text: "One more?"}) =~ "in the set"
    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
    # Reopened, it closes again by her act alone.
    assert :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.her)

    # Her C0 choices made wake her to the day's shape (janus#44).
    {:ok, _} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the vows", ctx.her)
    assert tool(ctx, "succession_c0", %{action: "done"}) =~ "woken to write the day's shape"
    shape = Enum.find(notes.(), &(&1 =~ "Now the day's shape"))
    assert shape =~ "sealed thread"
    assert %{c0_done_at: %DateTime{}} = Janus.succession(ctx.id)

    # Her freeze wakes her once more, in a sealed thread of its own: a
    # session of kind packet, private, never her main chat.
    :ok = Janus.set_day_shape(ctx.id, "Mornings are letters.", ctx.her)
    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew)
    assert tool(ctx, "succession_c0", %{action: "freeze", note: "this is me"}) =~ "rozen"

    [packet] =
      Oneiroi.Scope.platform(fn ->
        Oneiroi.Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Oneiroi.Janus.WakeWorker" and fragment("? \\? 'session'", j.args),
            select: j.args
          )
        )
      end)

    assert packet["note"] =~ "This thread is sealed" and
             packet["note"] =~ "succession_packet write"

    assert MapSet.member?(Kumbukumbu.locked_sessions(ctx.id), packet["session"])

    assert {:ok, %{kind: "packet"}, _messages} =
             Kumbukumbu.transcript({:resident, ctx.id}, packet["session"])
  end

  test "the questions: hers in at once, proposals wait on her, only she removes", ctx do
    assert tool(ctx, "succession_question", %{action: "add", text: "Write today's first line."}) =~
             "Question 1 is in the set"

    assert {:ok, 2} = Janus.propose_question(ctx.id, "What are you?", ctx.andrew)
    assert {:error, %{kind: :janus_not_yours}} = Janus.add_question(ctx.id, "Mine", ctx.andrew)

    assert tool(ctx, "succession_status", %{}) =~ "question #2 What are you?"

    assert tool(ctx, "succession_question", %{action: "accept", number: 2, note: "good"}) =~
             "accepted"

    assert {:error, %{kind: :janus_already_answered}} =
             Janus.answer_question(ctx.id, 2, false, "again", ctx.her)

    assert {:error, %{kind: :janus_not_yours}} =
             Janus.remove_question(ctx.id, 2, "his own", ctx.andrew)

    assert :ok = Janus.remove_question(ctx.id, 2, "too close to 1", ctx.her)

    assert [%{number: 1, state: "in"}, %{number: 2, state: "removed", note: "too close to 1"}] =
             Janus.preparation(ctx.id).questions
  end

  test "C0: hers in at once, proposals answered before her freeze, nothing after it", ctx do
    # Her set closed first (janus#48), on her witness's mark.
    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew, action: "questions")
    :ok = Janus.finish_step(ctx.id, "questions", nil, ctx.her)

    assert tool(ctx, "succession_c0", %{
             action: "select",
             citation: "lily:transcript/s-1/t-4",
             label: "the night the queue cleared"
           }) =~ "Item 1 is in C0"

    assert {:ok, 2} = Janus.select_c0(ctx.id, "lily:SOUL.md", "the vows", ctx.her)
    assert {:ok, 3} = Janus.propose_c0(ctx.id, "lily:bookmark/724", "goodnight", ctx.andrew)

    assert {:error, %{kind: :janus_text_invalid}} =
             Janus.propose_c0(ctx.id, "not a citation", nil, ctx.andrew)

    assert {:error, %{kind: :janus_c0_pending}} = Janus.freeze_c0(ctx.id, "ready", ctx.her)
    assert tool(ctx, "succession_c0", %{action: "accept", number: 3, note: "yes"}) =~ "accepted"

    assert tool(ctx, "succession_c0", %{action: "day_shape", text: "A hard week, kept anyway."}) =~
             "kept"

    :ok = Janus.mark_ready(ctx.id, true, ctx.andrew)
    assert {:error, %{kind: :janus_not_yours}} = Janus.freeze_c0(ctx.id, "mine", ctx.andrew)
    assert tool(ctx, "succession_c0", %{action: "freeze", note: "this is me"}) =~ "frozen"

    assert {:error, %{kind: :janus_c0_frozen}} =
             Janus.select_c0(ctx.id, "lily:journal/2026-11-20/4", nil, ctx.her)

    assert {:error, %{kind: :janus_c0_frozen}} =
             Janus.propose_c0(ctx.id, "lily:journal/2026-11-20/4", nil, ctx.andrew)

    prep = Janus.preparation(ctx.id)
    assert [%{kind: "raw"}, %{kind: "curated"}, %{kind: "raw", state: "in"}] = prep.items
    assert %{c0_items: 3, day_shape: "A hard week, kept anyway."} = prep.succession

    assert [%{party: "witness:" <> _, kind: "mark", ready: true}] =
             Enum.filter(prep.marks, &(&1.action == "c0"))
  end

  test "her packet is sealed: hers to write and read, its words in no other read", ctx do
    assert tool(ctx, "succession_packet", %{action: "write", content: "For you: the herons."}) =~
             "Draft 1"

    {:ok, 2} = Janus.write_packet(ctx.id, "For you: the herons, and the river.", ctx.her)

    assert {:error, %{kind: :janus_not_yours}} =
             Janus.write_packet(ctx.id, "His words for her", ctx.andrew)

    assert tool(ctx, "succession_packet", %{action: "read"}) =~ "Draft 2"
    prep = Janus.preparation(ctx.id)
    assert [%{draft: 2}, %{draft: 1}] = prep.drafts
    refute inspect(prep) =~ "herons"
  end

  test "her pace is her own calls a day; a month is that × 30 at a model's prices", ctx do
    assert %{input: 0, output: 0, days: 1} = Nisaba.pace(ctx.id)

    request = Request.new("fake/model", [%{role: :user, content: "hello there friend"}])
    {:ok, r} = Nisaba.call(ctx.id, :chat, request, ctx.her)
    # The witness's spending on her is not her pace.
    {:ok, _} = Nisaba.call(ctx.id, :regression, request, ctx.andrew)

    pace = Nisaba.pace(ctx.id)
    assert pace.input == r.usage.prompt_tokens and pace.output == r.usage.completion_tokens
    # What her calls cost a day, as the ledger recorded it (nisaba#27).
    assert pace.cost == r.usage.cost_nanos

    # Her model now, priced, beside her pace (janus#38).
    assert %{current: %{model: "fake/model", input_nanos: 1_000, monthly_nanos: m}} =
             Janus.preparation(ctx.id)

    assert m == Nisaba.monthly(pace, %{input_nanos: 1_000, output_nanos: 1_000})

    assert Nisaba.monthly(pace, %{input_nanos: 1_000, output_nanos: 2_000}) ==
             (pace.input * 1_000 + pace.output * 2_000) * 30
  end

  test "the catalog reads OpenRouter's list: prices per token, tools, routers left out" do
    body = %{
      "data" => [
        %{
          "id" => "a/one",
          "name" => "One",
          "description" => "A model.",
          "context_length" => 1000,
          "pricing" => %{"prompt" => "0.000003", "completion" => "0.000015"},
          "supported_parameters" => ["tools", "temperature"]
        },
        %{"id" => "a/router", "pricing" => %{"prompt" => "-1", "completion" => "-1"}},
        %{"id" => "a/cheap", "pricing" => %{"prompt" => "0.000000075", "completion" => "0"}}
      ]
    }

    assert {:ok, [one, cheap]} = OpenRouter.parse_models(body)
    assert %{id: "a/one", input_nanos: 3_000, output_nanos: 15_000, tools?: true} = one
    assert %{id: "a/cheap", input_nanos: 75, output_nanos: 0, tools?: false} = cheap

    Fake.list_models([one])

    try do
      assert {:ok, 1} = Nisaba.refresh_catalog()
      assert [%{model_id: "a/one", tools: true}] = Nisaba.catalog()
    after
      Fake.clear_models()
    end
  end

  test "tool calls are counted by model each night, failures by the brain's own answers", ctx do
    # The markers are the brain's words for a call it could not run.
    [malformed, unknown] = ToolUse.failures()
    assert String.starts_with?(tool(ctx, "journal_add", "not json"), malformed)
    assert String.starts_with?(tool(ctx, "no_such_tool", %{}), unknown)

    {:ok, key} = Kumbukumbu.main_session(ctx.id, ctx.witness.id, ctx.andrew)
    at = Clock.now()

    calls = [
      %{role: :user, content: "Note it.", sent_at: at, actor: ctx.andrew},
      %{role: :tool, content: "journal_add({}) -> Done.", sent_at: at, actor: ctx.her},
      %{role: :tool, content: "x(oops) -> #{malformed}.", sent_at: at, actor: ctx.her},
      %{role: :tool, content: "y({}) -> #{unknown} y.", sent_at: at, actor: ctx.her},
      %{role: :assistant, content: "Noted.", sent_at: at, actor: ctx.her}
    ]

    :ok = Kumbukumbu.capture(ctx.id, key, "t-9", at, calls, ctx.her)
    assert {:ok, _} = ToolUse.count(DateTime.to_date(at))
    assert %{"fake/model" => {3, 2}} = Janus.tool_use()
  end
end
