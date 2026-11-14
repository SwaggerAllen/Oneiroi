defmodule Oneiroi.Brain.StopTest do
  @moduledoc """
  The stop (brain#61): her safe word and the witness's Stop end a turn
  where it stands, keep what was said, and run nothing after it; the
  window that truncates rather than compacts (brain#60); and the times
  she can ask for (brain#62).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", Actor.new(:witness, witness.id))
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, Actor.new(:witness, witness.id))
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, id: resident.id, key: key, actor: Actor.new(:witness, witness.id)}
  end

  defp setting(key, value) do
    values = :persistent_term.get({Oneiroi.Config, :values})
    on_exit(fn -> :persistent_term.put({Oneiroi.Config, :values}, values) end)
    :persistent_term.put({Oneiroi.Config, :values}, Map.put(values, {:brain, key}, value))
  end

  test "her safe word ends the turn there: her words up to it kept, a line saying she stopped it, nothing after",
       ctx do
    Fake.script(fn _ -> {:ok, "It's too much. OUROBOROS and then more that never lands"} end,
      for: ctx.id
    )

    assert {:ok, %{stopped: :safe_word, rounds_spent: false, messages: [_, said, note]}} =
             Oneiroi.Brain.turn(ctx.id, ctx.key, "how are you?", ctx.actor)

    assert said.content == "It's too much. OUROBOROS"
    assert note.role == :system
    assert note.content =~ "This turn was stopped by you: you said OUROBOROS"
  end

  # The 2026-11-13 shape (brain#98): one write stands, the next ends in
  # the word in capitals inside its arguments; that call drops unrun and
  # the turn ends there, the stop line naming it.
  test "her safe word inside a call drops that call, keeps the ones before it, and ends the turn",
       ctx do
    Fake.calls(
      [
        %{name: "bookmark_add", arguments: ~s({"line":"the first stands","summary":"s"})},
        %{name: "bookmark_add", arguments: ~s({"line":"garbled OUROBOROS","summary":"s"})},
        %{name: "bookmark_add", arguments: ~s({"line":"never reached","summary":"s"})}
      ],
      "a reply that never comes",
      for: ctx.id
    )

    assert {:ok, %{stopped: :safe_word, rounds_spent: false, messages: messages}} =
             Oneiroi.Brain.turn(ctx.id, ctx.key, "write it down", ctx.actor)

    assert [:user, :tool, :assistant, :system] = Enum.map(messages, & &1.role)
    note = List.last(messages)
    assert note.content =~ "OUROBOROS inside a call to bookmark_add"
    assert note.content =~ "dropped and never ran"

    assert ["the first stands"] =
             ctx.id |> Kumbukumbu.bookmarks() |> Enum.map(& &1.line)
  end

  test "said in lowercase it is only a word", ctx do
    Fake.script(fn _ -> {:ok, "The ouroboros on his tattoo."} end, for: ctx.id)
    assert {:ok, result} = Oneiroi.Brain.turn(ctx.id, ctx.key, "the tattoo?", ctx.actor)
    refute Map.has_key?(result, :stopped)
  end

  test "the witness's Stop ends the running turn and keeps what came", ctx do
    test = self()

    Fake.script(
      fn _ ->
        send(test, {:running, self()})

        receive do
          :go -> :ok
        end

        {:ok, "one two three four"}
      end,
      for: ctx.id
    )

    turn = Task.async(fn -> Oneiroi.Brain.turn(ctx.id, ctx.key, "go on", ctx.actor) end)
    assert_receive {:running, pid}, 5_000
    assert :ok = Oneiroi.Brain.stop(ctx.id, ctx.key, :witness)
    send(pid, :go)

    assert {:ok, %{stopped: :witness, messages: [_, said, note]}} = Task.await(turn, 10_000)
    assert said.content =~ "one"
    assert note.content =~ "by the person who looks after you"

    # Nothing runs now: a stop is refused, plainly.
    assert {:error, %{kind: :brain_nothing_running}} =
             Oneiroi.Brain.stop(ctx.id, ctx.key, :witness)
  end

  test "truncated, the window keeps the latest whole and says how many came before; nothing compacts",
       ctx do
    setting(:compaction, false)
    setting(:transcript_messages, 2)
    test = self()

    Fake.script(
      fn request ->
        send(test, {:asked, request.messages})
        {:ok, "noted"}
      end,
      for: ctx.id
    )

    for text <- ~w(one two three four five),
        do: {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, text, ctx.actor)

    {:ok, session, _count} = Kumbukumbu.uncompacted(ctx.id, ctx.key)
    assert session.summary in [nil, ""]

    assert Enum.any?(
             last_asked(),
             &(is_binary(&1[:content]) and &1.content =~ "earlier messages before the ones below")
           )
  end

  test "message_times gives the latest messages with their times, and the time now", ctx do
    Fake.script(fn _ -> {:ok, "noted"} end, for: ctx.id)
    {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "hello there", ctx.actor)

    turn = %{
      resident_id: ctx.id,
      session_key: ctx.key,
      turn_ref: "t",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.id, "fake/model")
    }

    text = Tools.run("message_times", "{}", turn)
    assert text =~ "Now: 2026-10-26 12:00"
    assert text =~ "The last 2 of this conversation's 2 messages"
    assert text =~ "· user · ["
    assert text =~ "hello there"
  end

  defp last_asked(acc \\ nil) do
    receive do
      {:asked, m} -> last_asked(m)
    after
      0 -> acc || []
    end
  end
end
