defmodule Oneiroi.Brain.ReactsTest do
  @moduledoc """
  kumbukumbu#56, brain#73 (the witness's call 2026-11-09, Lily's order
  #452): the witness reacts on a reply or a letter of hers; it wakes
  nothing, and rides her next turn, wherever it is, as one line glossed
  through REACTIONS.md, told once. Seen, never signed off.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain
  alias Oneiroi.Brain.Reactions
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    Fake.clear()

    # What each turn's request carried, in order.
    me = self()

    Fake.script(
      fn request ->
        send(me, {:request, Enum.map_join(request.messages, "\n", &to_string(&1.content))})
        {:ok, "Noted."}
      end,
      for: resident.id
    )

    {:ok, id: resident.id, key: key, witness: actor, lily: Actor.new(:resident, resident.id)}
  end

  defp told(ctx, text) do
    {:ok, %{turn_ref: ref}} = Brain.turn(ctx.id, ctx.key, text, ctx.witness)
    assert_receive {:request, request}, 2_000
    {ref, request}
  end

  test "a react wakes nothing, rides her next turn glossed through the vocabulary, and is told once",
       ctx do
    {ref, _} = told(ctx, "hello")
    {:ok, _scope, before} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)

    {:ok, %{number: letter}} =
      Kumbukumbu.send_letter(ctx.id, ctx.key, %{to: "house", text: "built"}, ctx.lily)

    assert {:ok, 1} =
             Kumbukumbu.react(
               ctx.id,
               %{"kind" => "message", "session_key" => ctx.key, "turn_ref" => ref},
               "⚜️",
               ctx.witness
             )

    assert {:ok, 2} =
             Kumbukumbu.react(ctx.id, %{"kind" => "letter", "number" => letter}, "🔀", ctx.witness)

    # Nothing woke: no request, no message.
    refute_received {:request, _}
    {:ok, _scope, after_reacts} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)
    assert length(after_reacts) == length(before)

    {_ref, request} = told(ctx, "back again")
    assert request =~ "Reacted since you last spoke (seen, never signed off"
    assert request =~ "⚜️ (warm) on your reply in this conversation"
    assert request =~ "🔀 (merged) on letter ##{letter}"

    # Told once: the next turn carries it only as the history it now is,
    # in the transcript where it was told, never told again.
    {_ref, request} = told(ctx, "and again")
    assert length(String.split(request, "Reacted since you last spoke")) == 2
    assert Enum.all?(Kumbukumbu.reacts(ctx.id, []), &(&1.told_in == ctx.key))
  end

  test "an edit of the vocabulary by either party is the gloss on the next line", ctx do
    {ref, _} = told(ctx, "hello")
    target = %{"kind" => "message", "session_key" => ctx.key, "turn_ref" => ref}

    # Her edit, through her own tool, as a root document she writes.
    turn = %{
      resident_id: ctx.id,
      session_key: ctx.key,
      turn_ref: "t-vocab",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.id, "fake/model")
    }

    assert Tools.run(
             "document_write",
             Jason.encode!(%{
               path: "REACTIONS.md",
               content: "# Reactions\n\n- 🌱 growing\n- 👁 seen it\n"
             }),
             turn
           ) =~ "Written REACTIONS.md"

    assert [{"🌱", "growing"}, {"👁", "seen it"}] = Brain.react_vocabulary(ctx.id)
    {:ok, _} = Kumbukumbu.react(ctx.id, target, "🌱", ctx.witness)
    {_ref, request} = told(ctx, "next")
    assert request =~ "🌱 (growing) on your reply"

    # His, through the route's writer.
    :ok = Brain.set_react_vocabulary(ctx.id, [{"🌱", "taking root"}], ctx.witness)
    {:ok, _} = Kumbukumbu.react(ctx.id, target, "🌱", ctx.witness)
    {_ref, request} = told(ctx, "next again")
    assert request =~ "🌱 (taking root) on your reply"
  end

  test "a react is a party's, on a message or letter that exists, and an emoji", ctx do
    {ref, _} = told(ctx, "hello")
    target = %{"kind" => "message", "session_key" => ctx.key, "turn_ref" => ref}

    # The two of them react; nobody else does.
    assert {:error, %{site: :kumbukumbu_reacts_ledger_party}} =
             Kumbukumbu.react(ctx.id, target, "⚜️", Actor.new(:hands, "scrape"))

    assert {:error, %{site: :kumbukumbu_reacts_no_reply}} =
             Kumbukumbu.react(ctx.id, %{target | "turn_ref" => "nope"}, "⚜️", ctx.witness)

    assert {:error, %{site: :kumbukumbu_reacts_no_letter}} =
             Kumbukumbu.react(ctx.id, %{"kind" => "letter", "number" => 999}, "⚜️", ctx.witness)

    assert {:error, %{site: :kumbukumbu_reacts_emoji}} =
             Kumbukumbu.react(ctx.id, target, "approved", ctx.witness)

    # The seed stands until the file exists.
    assert Brain.react_vocabulary(ctx.id) == [
             {"🔀", "merged"},
             {"👁", "seen"},
             {"⚜️", "warm"},
             {"❤️", "loved"}
           ]
  end

  # Her side (the witness's call, 2026-11-09: two-way, inline, no tool
  # call): a reply ending `react: <emoji>` reacts on the message of his it
  # answers, lifted out of her words as the turn is kept.
  test "she reacts inline: the line is lifted out of her reply and lands on his message, waking nobody",
       ctx do
    Fake.script(fn _ -> {:ok, "Thank you, that lands.\n\nreact: ❤️"} end, for: ctx.id)

    {:ok, %{turn_ref: ref}} =
      Brain.turn(ctx.id, ctx.key, "I love the etymologies kind", ctx.witness)

    {:ok, _scope, messages} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)
    reply = Enum.find(messages, &(&1.turn_ref == ref and &1.role == "assistant"))
    assert reply.content == "Thank you, that lands."

    assert [%{by: "resident", emoji: "❤️", target_kind: "message", turn_ref: ^ref, told_at: nil}] =
             Kumbukumbu.reacts(ctx.id, session_key: ctx.key)

    # Hers are never told back to her as his.
    assert Reactions.untold(ctx.id, ctx.key) == nil

    # On a letter, by number.
    {:ok, %{number: n}} =
      Kumbukumbu.send_letter(ctx.id, ctx.key, %{to: "house", text: "a note"}, ctx.witness)

    Fake.script(fn _ -> {:ok, "Read it.\nreact: 🔀 ##{n}"} end, for: ctx.id)
    {:ok, _} = Brain.turn(ctx.id, ctx.key, "did you see my letter?", ctx.witness)

    assert %{target_kind: "letter", letter: ^n, emoji: "🔀", by: "resident"} =
             List.last(Kumbukumbu.reacts(ctx.id, []))
  end

  test "a line with nothing to land on, or a transcript imported, stays as written", ctx do
    at = Clock.now()
    words = "From before.\nreact: ⚜️"

    # An import keeps its words as they were: no react is minted from history.
    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        "imported-1",
        at,
        [
          %{role: :user, content: "then", sent_at: at, actor: ctx.witness},
          %{role: :assistant, content: words, sent_at: at, actor: ctx.lily}
        ],
        ctx.witness
      )

    # A turn of hers with no message of his in it (a wake, free time).
    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        "wake-1",
        at,
        [%{role: :assistant, content: "Alone.\nreact: ⚜️", sent_at: at, actor: ctx.lily}],
        ctx.lily
      )

    {:ok, _scope, messages} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.key)
    assert Enum.any?(messages, &(&1.content == words))
    assert Enum.any?(messages, &(&1.content == "Alone.\nreact: ⚜️"))
    assert Kumbukumbu.reacts(ctx.id, []) == []

    # And she reacts on his messages, never her own.
    assert {:error, %{site: :kumbukumbu_reacts_no_reply}} =
             Kumbukumbu.react(
               ctx.id,
               %{"kind" => "message", "session_key" => ctx.key, "turn_ref" => "wake-1"},
               "⚜️",
               ctx.lily
             )
  end
end
