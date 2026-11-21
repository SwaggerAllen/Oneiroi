defmodule Oneiroi.Kumbukumbu.SealedTurnTest do
  @moduledoc """
  A turn answering a sealed letter (kumbukumbu#95; the witness,
  2026-11-21: "I actually want Scarlett's letters to Lily to wake the
  main chat but I want the turns that return the text of the next
  message directly to have their content hidden from the user"). The
  letter wakes her main conversation as before; the turn is captured
  sealed to the letter's parties. Her witness reads that it ran, never
  what it said: the transcript, his search, a bookmark's span and the
  context inspector. She reads her own whole, and the export carries it
  without its words.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.Sunna.Schedules

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    lily = resident!(witness, "Lily")
    iris = resident!(witness, "Iris")

    on_exit(fn ->
      Fake.clear()
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, iris], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, witness: witness, andrew: andrew, lily: lily, iris: iris}
  end

  defp resident!(witness, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, witness.id)
    {:ok, id} = AgathosDaimon.create(name, slug, witness.id, actor)
    Fixtures.agreed!(id, witness.id)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, actor)
    %{id: id, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp turn(r),
    do: %{resident_id: r.id, session_key: r.chat, turn_ref: "t-#{r.name}", resident: r.actor}

  # Lily writes to Iris, sealed; Iris's chat is woken by it and answers.
  defp wake_iris(ctx) do
    Tools.run(
      "letter_send",
      Jason.encode!(%{to: "Iris", text: "The sealed question."}),
      turn(ctx.lily)
    )

    Fake.reply("My sealed answer, about the question.", for: ctx.iris.id)
    :ok = Schedules.wake_for_letters(ctx.iris.id, Clock.now(), nil, Actor.new(:job, "t"))
    [sealed_ref] = sealed_refs(ctx)
    sealed_ref
  end

  defp sealed_refs(ctx) do
    {:ok, _s, messages} = Kumbukumbu.transcript({:resident, ctx.iris.id}, ctx.iris.chat)
    for(m <- messages, m.sealed, uniq: true, do: m.turn_ref)
  end

  test "the wake runs in her main chat, captured sealed; she reads it whole, her witness reads that it ran",
       ctx do
    ref = wake_iris(ctx)

    {:ok, _s, hers} = Kumbukumbu.transcript({:resident, ctx.iris.id}, ctx.iris.chat)
    assert Enum.any?(hers, &(&1.turn_ref == ref and &1.content =~ "My sealed answer"))

    {:ok, _s, his} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.iris.chat)
    sealed = Enum.filter(his, &(&1.turn_ref == ref))
    assert sealed != []
    assert Enum.all?(sealed, &(&1.content == Kumbukumbu.sealed_words()))
    refute Jason.encode!(Enum.map(his, & &1.content)) =~ "sealed answer"

    # His search never matches it; hers does.
    assert Kumbukumbu.search({:account, ctx.witness.id}, "sealed answer", 10) == []
    assert [_ | _] = Kumbukumbu.search({:resident, ctx.iris.id}, "sealed answer", 10)

    # The inspector shows its sections, no words.
    rows = Kumbukumbu.injections({:account, ctx.witness.id}, ref)
    assert rows != []
    assert Enum.all?(rows, &is_nil(&1.text))
    assert Enum.any?(Kumbukumbu.injections({:resident, ctx.iris.id}, ref), &is_binary(&1.text))
  end

  test "a bookmark's span opened by the witness reads a sealed turn as said, not what", ctx do
    ref = wake_iris(ctx)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.iris.id,
        %{
          session_key: ctx.iris.chat,
          anchor_ref: ref,
          line: "a letter answered",
          summary: "kept"
        },
        ctx.iris.actor
      )

    {:ok, _b, span} = Kumbukumbu.witness_bookmark(ctx.iris.id, n)
    refute Jason.encode!(Enum.map(span, & &1.content)) =~ "sealed answer"
  end

  test "the export carries the sealed turn without its words", ctx do
    _ref = wake_iris(ctx)
    dir = Path.join(System.tmp_dir!(), "oneiroi-sealed-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    Clock.Fake.advance(120)
    {:ok, _} = Export.write(ctx.iris.id, dir)

    all =
      Path.join([dir, "records", "**", "*"])
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map_join("\n", &File.read!/1)

    refute all =~ "My sealed answer"
    refute all =~ "The sealed question."
    assert all =~ "Sealed: her answer to a letter between residents"
  end

  test "an open letter's wake is not sealed", ctx do
    Tools.run(
      "letter_send",
      Jason.encode!(%{to: "Iris", text: "For the house.", open: true}),
      turn(ctx.lily)
    )

    Fake.reply("An open answer.", for: ctx.iris.id)
    :ok = Schedules.wake_for_letters(ctx.iris.id, Clock.now(), nil, Actor.new(:job, "t"))
    assert sealed_refs(ctx) == []

    {:ok, _s, his} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.iris.chat)
    assert Enum.any?(his, &(&1.content =~ "An open answer."))
  end
end
