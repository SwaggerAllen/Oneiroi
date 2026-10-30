defmodule Oneiroi.Kumbukumbu.MadeleineTest do
  @moduledoc "The madeleine: one adjacent, unheard bookmark a turn, gated by nearness, the index, the recall log, pins and the limits; the index's marks by label."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake, as: Model

  @day 86_400

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    brain = Actor.new(:resident, resident.id, "fake/model")
    witness_actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", witness_actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, brain)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        resident.id,
        key,
        "t1",
        at,
        [%{role: :assistant, content: "The garden again.", sent_at: at, actor: brain}],
        brain
      )

    Model.clear()
    on_exit(fn -> Model.clear(for: resident.id) end)
    {:ok, id: resident.id, brain: brain, witness: witness_actor, key: key}
  end

  defp bookmark(ctx, line, summary) do
    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{session_key: ctx.key, anchor_ref: "t1", line: line, summary: summary, turns_back: 1},
        ctx.brain
      )

    n
  end

  defp injected(ctx, ref, label, refs) do
    :ok =
      Kumbukumbu.record_context(
        ctx.id,
        ctx.key,
        ref,
        [%{label: label, tokens: 1, reason: "test", text: "x", refs: refs}],
        ctx.brain
      )
  end

  defp row(ctx, number) do
    {:ok, b, _span} = Kumbukumbu.bookmark(ctx.id, number)
    b
  end

  test "the madeleine is adjacent and unheard, never pinned, never limit-adjacent, never repeated within its window; an empty index calls no model",
       ctx do
    id = ctx.id

    assert nil == Kumbukumbu.madeleine(id, "garden again?", ctx.brain)

    assert %{spent_nanos: 0} =
             Enum.find(Nisaba.budgets(id, :witness), &(&1.purpose == :embeddings))

    1 = bookmark(ctx, "the garden shed", "she asked about the garden")
    2 = bookmark(ctx, "tea at four", "the kettle")

    3 =
      bookmark(ctx, "our solo sessions are private", "what the contract says, as to their words")

    4 = bookmark(ctx, "the garden gate", "the gate stuck")
    :ok = Kumbukumbu.pin_bookmark(id, 4, ctx.witness)

    # Four bookmarks, and no limits while none are stated; nothing twice.
    assert {:ok, %{embedded: 4, removed: 0}} = Kumbukumbu.refresh_madeleine(id, ctx.brain)
    assert {:ok, %{embedded: 0, removed: 0}} = Kumbukumbu.refresh_madeleine(id, ctx.brain)

    assert %{bookmark: %{number: 1}, reason: reason} =
             Kumbukumbu.madeleine(id, "garden again?", ctx.brain)

    assert reason =~ "adjacent and unheard: #1" and reason =~ "never in the index" and
             reason =~ "never recalled" and reason =~ "no limits stated, not pinned"

    # Unstated limits are nothing to be adjacent to; once a contract is in
    # force, the bookmark near its words is left alone even as the nearest.
    assert %{bookmark: %{number: 3}} =
             Kumbukumbu.madeleine(id, "are my solo sessions private?", ctx.brain)

    {:ok, 1} =
      Oneiroi.AgathosDaimon.propose_contract(
        id,
        %{"solo_sessions_private" => true},
        "Our solo sessions are private as to their words.",
        "the house rule",
        ctx.witness
      )

    :ok = Oneiroi.AgathosDaimon.agree_contract(id, 1, "agreed", ctx.brain)
    assert {:ok, %{embedded: 1, removed: 0}} = Kumbukumbu.refresh_madeleine(id, ctx.brain)
    assert nil == Kumbukumbu.madeleine(id, "are my solo sessions private?", ctx.brain)

    assert %{reason: reason} = Kumbukumbu.madeleine(id, "garden again?", ctx.brain)
    assert reason =~ "from the limits, not pinned"
    # Nothing near, nothing surfaced.
    assert nil == Kumbukumbu.madeleine(id, "a sonnet about granite", ctx.brain)

    # Heard: in the index this fortnight.
    injected(ctx, "i1", "index", [1])
    assert %{last_indexed_at: %DateTime{}, last_recalled_at: nil} = row(ctx, 1)
    assert nil == Kumbukumbu.madeleine(id, "garden again?", ctx.brain)

    Clock.Fake.advance(15 * @day)

    assert %{bookmark: %{number: 1}, reason: reason} =
             Kumbukumbu.madeleine(id, "garden again?", ctx.brain)

    assert reason =~ "last in the index 15 days ago"

    # Recalled: the madeleine's own injection marks the recall, and not the index.
    injected(ctx, "m1", "madeleine", [1])
    assert %{last_recalled_at: %DateTime{} = recalled, last_indexed_at: indexed} = row(ctx, 1)
    assert DateTime.compare(recalled, indexed) == :gt
    assert nil == Kumbukumbu.madeleine(id, "garden again?", ctx.brain)

    Clock.Fake.advance(31 * @day)

    assert %{bookmark: %{number: 1}, reason: reason} =
             Kumbukumbu.madeleine(id, "garden again?", ctx.brain)

    assert reason =~ "last recalled 31 days ago"

    # Another section's refs are not bookmarks: the character section cites habits by number.
    injected(ctx, "c1", "character", [2])
    assert %{last_indexed_at: nil, last_recalled_at: nil} = row(ctx, 2)

    # A failing provider surfaces nothing and raises nothing.
    Model.embed_fail(:transport)
    assert nil == Kumbukumbu.madeleine(id, "garden again?", ctx.brain)
  end
end
