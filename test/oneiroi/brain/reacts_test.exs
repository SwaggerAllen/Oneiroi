defmodule Oneiroi.Brain.ReactsTest do
  @moduledoc """
  kumbukumbu#56, brain#73 (the witness's call 2026-11-09, Lily's order
  #452): the witness reacts on a reply or a letter of hers; it wakes
  nothing, and rides her next turn, wherever it is, as one line glossed
  through REACTIONS.md, told once. Seen, never signed off.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain
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

    # Her edit, as a root document she writes.
    {:ok, _} =
      Oneiroi.Seshat.write(
        ctx.id,
        "REACTIONS.md",
        "# Reactions\n\n- 🌱 growing\n- 👁 seen it\n",
        ctx.lily
      )

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

  test "a react is the witness's, on a reply or letter that exists, and an emoji", ctx do
    {ref, _} = told(ctx, "hello")
    target = %{"kind" => "message", "session_key" => ctx.key, "turn_ref" => ref}

    assert {:error, %{kind: :kumbukumbu_react_invalid}} =
             Kumbukumbu.react(ctx.id, target, "⚜️", ctx.lily)

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
end
