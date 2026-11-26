defmodule Oneiroi.Janus.PreparationTest do
  @moduledoc """
  A succession's preparation (janus#6 to #11, nisaba#24, #25,
  kumbukumbu#114): the witness's envelope and the pool inside it, the
  questions only she decides, C0 with its proposals, the day's shape and
  her freeze, the sealed packet, the catalog and her pace, and the tool
  calls on Oneiroi counted by model with no words leaving memory.
  """
  use Oneiroi.DataCase, async: false

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

  test "the pool: his envelope first, her picks inside it, his anywhere, never without tools",
       ctx do
    assert {:error, %{kind: :janus_no_envelope}} =
             Janus.add_to_pool(ctx.id, "fake/model", ctx.her)

    assert tool(ctx, "succession_catalog", %{}) =~ "not stated the envelope"

    # $5 and $20 a million tokens.
    :ok = Janus.set_envelope(ctx.id, 5_000, 20_000, ctx.andrew)

    assert {:error, %{kind: :janus_not_the_witness}} =
             Janus.set_envelope(ctx.id, 9_000, 9_000, ctx.her)

    catalog = tool(ctx, "succession_catalog", %{})
    assert catalog =~ "fake/model: $1.00 in, $1.00 out"
    refute catalog =~ "fake/dear"
    refute catalog =~ "fake/mute"

    assert tool(ctx, "succession_pool", %{action: "add", model: "fake/model"}) =~ "in the pool"

    assert {:error, %{kind: :janus_pool_outside_envelope}} =
             Janus.add_to_pool(ctx.id, "fake/dear", ctx.her)

    assert :ok = Janus.add_to_pool(ctx.id, "fake/dear", ctx.andrew)

    assert {:error, %{kind: :janus_pool_no_tools}} =
             Janus.add_to_pool(ctx.id, "fake/mute", ctx.andrew)

    assert {:error, %{kind: :janus_pool_unknown_model}} =
             Janus.add_to_pool(ctx.id, "nobody/none", ctx.andrew)

    # He removes only his own; she removes any.
    assert {:error, %{kind: :janus_not_yours}} =
             Janus.remove_from_pool(ctx.id, "fake/model", "mine?", ctx.andrew)

    assert tool(ctx, "succession_pool", %{action: "remove", model: "fake/dear", note: "too dear"}) =~
             "out of the pool"

    prep = Janus.preparation(ctx.id)

    assert [%{row: %{model: "fake/model", removed_at: nil}}, %{row: %{removed_note: "too dear"}}] =
             prep.pool

    assert tool(ctx, "succession_status", %{}) =~ "Pool (1): fake/model (yours)"
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
    assert [%{party: "witness:" <> _, ready: true}] = prep.ready
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
