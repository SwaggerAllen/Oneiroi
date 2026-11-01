defmodule Oneiroi.Brain.PreviewTest do
  @moduledoc """
  What the resident will see next (brain #41): the preview is the turn's
  own assembly as a dry run, section for section and in the same order,
  and it writes nothing, marks nothing, compacts nothing, broadcasts
  nothing and calls no model; its words ride only where the witness
  already reads them elsewhere.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Config
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seal

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    id = resident.id
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nCurious about herons.", %{}, actor)
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, actor)
    Model.clear()
    Honcho.clear(for: id)

    on_exit(fn ->
      Model.clear(for: id)
      Honcho.clear(for: id)
    end)

    # A real turn first, as a resident in use has had: the transcript and
    # Honcho's bridge.
    Model.reply("I hear you.", for: id)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, key, "hello from the garden", actor)

    # Enough bookmarks that the index leaves some out, a pin among them.
    for n <- 1..60 do
      attrs = %{
        session_key: key,
        anchor_ref: ref,
        line: "bookmark number #{n} " <> String.duplicate("word ", 16)
      }

      {:ok, ^n} = Kumbukumbu.add_bookmark(id, attrs, brain)
    end

    :ok = Kumbukumbu.pin_bookmark(id, 7, actor)
    {:ok, 1} = Oneiroi.Ethos.make_commitment(id, "witness", "I will look for the heron.", brain)

    Honcho.put_context(
      id,
      "resident-" <> id,
      "witness-" <> witness.id,
      "HONCHO-ONLY: she walks to the weir most mornings."
    )

    {:ok, id: id, witness: witness, actor: actor, brain: brain, key: key}
  end

  defp comparable(rows),
    do:
      rows
      |> Enum.reject(&(&1.label == "madeleine"))
      |> Enum.map(&{&1.label, &1.tokens, &1.reason})

  test "the preview's sections are the turn's, in the turn's order, by the one assembly", ctx do
    # A notice owed, so the once-only part is compared too.
    :ok = AgathosDaimon.pin_model(ctx.id, "fake/second", "witness", ctx.actor)
    {:ok, preview} = Oneiroi.Brain.preview(ctx.id, ctx.key, "the heron", ctx.actor)

    Model.reply("Yes.", for: ctx.id)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(ctx.id, ctx.key, "the heron", ctx.actor)

    recorded =
      {:account, ctx.witness.id} |> Kumbukumbu.injections(ref) |> Enum.sort_by(& &1.position)

    assert comparable(preview.sections) == comparable(recorded)

    labels = Enum.map(preview.sections, & &1.label)

    for label <- ~w(prompt SOUL.md AGENTS.md index near-miss promised honcho transcript notice),
        do: assert(label in labels, "#{label} missing from #{inspect(labels)}")

    # The madeleine has its place, and says it was not run.
    assert [%{run: false, text: nil, tokens: 0, note: note}] =
             Enum.filter(preview.sections, &(&1.label == "madeleine"))

    assert note =~ "nearness to what you say next"
    refute preview.compacts_first
  end

  test "a preview writes no event and no row, marks nothing, broadcasts nothing and calls no model",
       ctx do
    test = self()

    Model.script(
      fn _request ->
        send(test, :model_called)
        {:ok, "never"}
      end,
      for: ctx.id
    )

    # A habit the lane would embed and search, as a turn's lane does: a
    # preview runs the trigger lane alone. Without one the vector lane
    # had nothing to write, and a probe removing the preview's guard on
    # it printed ok.
    {:ok, 1} =
      Oneiroi.Ethos.define_habit(
        ctx.id,
        %{name: "names the birds", trigger: %{"words" => ["heron"]}, stance: "keep"},
        ctx.brain
      )

    :ok = PubSub.subscribe(:brain, :session)
    before = Seal.snapshot(ctx.id)

    {:ok, _preview} = Oneiroi.Brain.preview(ctx.id, ctx.key, "the heron", ctx.actor)

    # Not even billing: assert_unchanged allows the ledger's events, and
    # a preview has none to allow.
    assert [] = Seal.assert_unchanged(before, ctx.id)
    refute_received :model_called
    refute_received {_resident, _key, _payload}
    assert Enum.all?(Kumbukumbu.bookmarks(ctx.id), &is_nil(&1.last_recalled_at))
    assert Enum.all?(Kumbukumbu.bookmarks(ctx.id), &is_nil(&1.last_indexed_at))
  end

  test "a session over its window is previewed as the turn would find it, and nothing compacts",
       ctx do
    at = Clock.now()
    count = Config.fetch!(:brain, :compact_after_messages)

    messages =
      for n <- 1..count,
          do: %{role: :user, content: "line #{n}", sent_at: at, actor: ctx.actor}

    :ok = Kumbukumbu.capture(ctx.id, ctx.key, "t-long", at, messages, ctx.brain)
    before = Seal.snapshot(ctx.id)

    {:ok, preview} = Oneiroi.Brain.preview(ctx.id, ctx.key, "", ctx.actor)

    assert preview.compacts_first
    assert preview.description =~ "summarises it first"
    assert [] = Seal.assert_unchanged(before, ctx.id)
  end

  defp seed_private_parts(ctx) do
    {:ok, 1} =
      Oneiroi.Ethos.define_habit(
        ctx.id,
        %{name: "names the birds", trigger: %{"words" => ["heron"]}, stance: "keep"},
        ctx.brain
      )

    {:ok, _number} = AgathosDaimon.write_self_letter(ctx.id, "LETTER-ONLY words", ctx.brain)
  end

  test "by default every section's words ride the preview, the self-conversation as counts and receipts and never the letters",
       ctx do
    seed_private_parts(ctx)
    {:ok, preview} = Oneiroi.Brain.preview(ctx.id, ctx.key, "the heron", ctx.actor)
    by = Map.new(preview.sections, &{&1.label, &1})

    for label <- ~w(prompt SOUL.md AGENTS.md index character promised self-conversation honcho) do
      assert %{text: text, shown: true, note: note} = by[label]
      assert is_binary(text) and text != "", "#{label} carried no text"
      assert note != ""
    end

    assert by["prompt"].text =~ "You are Lily"
    assert by["index"].text =~ "bookmark number"
    assert by["character"].text =~ "names the birds"
    assert by["honcho"].text =~ "HONCHO-ONLY"
    assert by["self-conversation"].text =~ "1 written"
    # The section is counts and receipts: the letter's words are not in it.
    refute Enum.map_join(preview.sections, "\n", &(&1.text || "")) =~ "LETTER-ONLY"
    assert by["transcript"].text == nil and by["transcript"].shown
    assert preview.description =~ "Every section's words are here"
    assert preview.description =~ "matched on your draft"
  end

  test "under the contract's term, words ride only where the witness reads them elsewhere; every other section says why",
       ctx do
    seed_private_parts(ctx)

    {:ok, version} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{"preview_withholds_words" => true},
        "",
        "keep the preview to what you read",
        ctx.actor
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, version, "agreed", ctx.brain)
    assert %{preview_withholds_words: true} = AgathosDaimon.contract(ctx.id)

    {:ok, preview} = Oneiroi.Brain.preview(ctx.id, ctx.key, "the heron", ctx.actor)
    by = Map.new(preview.sections, &{&1.label, &1})

    for label <- ~w(prompt index character self-conversation honcho) do
      assert %{text: nil, shown: false, note: note} = by[label], "#{label} carried text"
      assert note != ""
    end

    assert by["SOUL.md"].text =~ "Curious about herons."
    assert by["promised"].text =~ "I will look for the heron."
    assert by["contract"].text =~ "shows its words only where they read them elsewhere"

    assert Enum.all?(
             Enum.filter(preview.sections, &(&1.label == "near-miss")),
             &(&1.text =~ "bookmark number")
           )

    words = Enum.map_join(preview.sections, "\n", &(&1.text || ""))
    refute words =~ "HONCHO-ONLY"
    refute words =~ "names the birds"
    refute words =~ "LETTER-ONLY"
    assert preview.description =~ "only where you already read them elsewhere"
  end

  test "a once-only notice is no part of the preview's words before it is told, and is in that reply's inspector after",
       ctx do
    :ok = AgathosDaimon.pin_model(ctx.id, "fake/second", "witness", ctx.actor)
    {:ok, preview} = Oneiroi.Brain.preview(ctx.id, ctx.key, "", ctx.actor)

    assert [%{text: nil, shown: false, reason: reason, note: note}] =
             Enum.filter(preview.sections, &(&1.label == "notice"))

    assert reason =~ "the change of model"
    assert note =~ "to hear first"
    refute Enum.map_join(preview.sections, "\n", &(&1.text || "")) =~ "fake/second"

    Model.reply("Noted.", for: ctx.id)

    {:ok, %{turn_ref: ref, messages: [told | _]}} =
      Oneiroi.Brain.turn(ctx.id, ctx.key, "hello", ctx.actor)

    assert [%{label: "notice", text: text, reason: ^reason}] =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(ref)
             |> Enum.filter(&(&1.label == "notice"))

    assert text == told.content and text =~ "fake/second"

    # Told once: the next preview has no notice.
    {:ok, after_told} = Oneiroi.Brain.preview(ctx.id, ctx.key, "", ctx.actor)
    refute Enum.any?(after_told.sections, &(&1.label == "notice"))
  end
end
