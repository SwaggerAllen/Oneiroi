defmodule Oneiroi.Kumbukumbu.PassagesTest do
  @moduledoc """
  The transcripts by meaning (kumbukumbu #49, the resident's letter
  #26): messages cut into passages and embedded once, the nearest found
  by what they say rather than their exact words, through
  transcript_search beside the phrase hits.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Uses
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Passages
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)

    say = fn ref, role, content ->
      at = Clock.now()
      Clock.Fake.advance(1)
      who = if role == :user, do: actor, else: brain

      :ok =
        Kumbukumbu.capture(
          resident.id,
          key,
          ref,
          at,
          [%{role: role, content: content, sent_at: at, actor: who}],
          brain
        )
    end

    {:ok, id: resident.id, key: key, actor: actor, brain: brain, say: say}
  end

  test "a long message is cut on paragraphs within the bound, and a long paragraph at it" do
    bound = Oneiroi.Config.fetch!(:kumbukumbu, :passage_chars)
    short = "One.\n\nTwo."
    assert Passages.cut(short) == ["One.\n\nTwo."]

    long = Enum.map_join(1..6, "\n\n", fn i -> String.duplicate("w#{i} ", div(bound, 8)) end)
    parts = Passages.cut(long)
    assert length(parts) > 1
    assert Enum.all?(parts, &(byte_size(&1) <= bound))

    huge = String.duplicate("x", bound * 2 + 10)
    assert [a, b, c] = Passages.cut(huge)
    assert String.length(a) == bound and String.length(b) == bound and String.length(c) == 10
  end

  test "each message is embedded once, and transcript_search finds a turn by what it says", ctx do
    ctx.say.("t-heron", :user, "We stood by the weir at dawn and a heron fished.")
    ctx.say.("t-taxes", :assistant, "The quarterly estimate is due on the fifteenth.")

    assert {:ok, %{messages: 2, passages: 2, more: false}} =
             Kumbukumbu.refresh_passages(ctx.id, ctx.actor)

    assert {:ok, %{messages: 0, passages: 0}} = Kumbukumbu.refresh_passages(ctx.id, ctx.actor)

    turn = %{resident_id: ctx.id, session_key: ctx.key, turn_ref: "t-ask", resident: ctx.brain}

    # No message holds the phrase; the heron turn is nearest the meaning.
    out = Tools.run("transcript_search", Jason.encode!(%{q: "heron fishing at the weir"}), turn)
    assert out =~ "By phrase:\nNo message holds that phrase."
    [_, meaning] = String.split(out, "By meaning:\n")
    assert [first | _] = String.split(meaning, "\n")
    assert first =~ "[#{ctx.key}/t-heron] user, "
    assert first =~ "a heron fished."

    # Retrieval counts a meaning hit as it counts a phrase hit.
    assert [_ | _] = Uses.from_call("transcript_search", %{}, out, "lily")

    # A phrase hit is not repeated by meaning; `by` narrows.
    both = Tools.run("transcript_search", Jason.encode!(%{q: "quarterly estimate"}), turn)
    [phrase_part, meaning_part] = String.split(both, "By meaning:\n")
    assert phrase_part =~ "t-taxes"
    refute meaning_part =~ "t-taxes"

    only = Tools.run("transcript_search", Jason.encode!(%{q: "weir", by: "phrase"}), turn)
    refute only =~ "By meaning"
    assert only =~ "t-heron"
  end

  test "new messages after a run are embedded by the next, and a batch says more waits", ctx do
    ctx.say.("t-1", :user, "first words")
    {:ok, %{messages: 1}} = Kumbukumbu.refresh_passages(ctx.id, ctx.actor)
    ctx.say.("t-2", :assistant, "second words")
    assert {:ok, %{messages: 1, more: false}} = Kumbukumbu.refresh_passages(ctx.id, ctx.actor)
  end
end
