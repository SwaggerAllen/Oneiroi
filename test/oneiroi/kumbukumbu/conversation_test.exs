defmodule Oneiroi.Kumbukumbu.ConversationTest do
  @moduledoc "The aggregate, pure: a turn captured twice is one event, a failure resolves once."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Kumbukumbu.Commands
  alias Oneiroi.Kumbukumbu.Conversation
  alias Oneiroi.Kumbukumbu.Events

  @at ~U[2026-10-29 12:00:00.000000Z]
  @actor Actor.new(:resident, "r1", "fake/model")
  @messages [
    %{
      role: "user",
      content: "hi",
      sent_at: "2026-10-29T12:00:00.000000Z",
      hash: "h1",
      actor: %{kind: "steward", id: "a1"}
    },
    %{
      role: "assistant",
      content: "hello",
      sent_at: "2026-10-29T12:00:01.000000Z",
      hash: "h2",
      actor: %{kind: "resident", id: "r1", model: "fake/model"}
    }
  ]

  defp opened do
    Conversation.apply(%Conversation{}, %Events.SessionOpened{
      actor: @actor,
      at: @at,
      id: "r1-s1",
      session_key: "s1",
      kind: "main",
      adapter: "brain",
      participants: ["a1"]
    })
  end

  defp capture(turn_ref \\ "t1") do
    %Commands.CaptureTurn{
      actor: @actor,
      at: @at,
      id: "r1-s1",
      session_key: "s1",
      turn_ref: turn_ref,
      started_at: @at,
      messages: @messages
    }
  end

  test "a session opens once, with a kind memory captures" do
    open = %Commands.OpenSession{
      actor: @actor,
      at: @at,
      id: "r1-s1",
      session_key: "s1",
      kind: "main",
      adapter: "brain",
      participants: ["a1"]
    }

    assert %Events.SessionOpened{kind: "main"} = Conversation.execute(%Conversation{}, open)
    assert [] = Conversation.execute(opened(), open)

    assert {:error, :kind_invalid} =
             Conversation.execute(%Conversation{}, %{open | kind: "regression"})

    assert {:error, :no_such_session} = Conversation.execute(%Conversation{}, capture())
  end

  test "a turn captured twice is one event, and an empty turn is refused" do
    assert %Events.TurnCaptured{turn_ref: "t1"} =
             event = Conversation.execute(opened(), capture())

    once = Conversation.apply(opened(), event)
    # The same content under another ref is the same turn: the key is the content's.
    assert [] = Conversation.execute(once, capture("t2"))
    assert {:error, :empty_turn} = Conversation.execute(opened(), %{capture() | messages: []})

    different = %{capture("t3") | started_at: ~U[2026-10-29 12:05:00.000000Z]}
    assert %Events.TurnCaptured{turn_ref: "t3"} = Conversation.execute(once, different)
  end

  test "a capture failure resolves once, by a named way, with a note" do
    failed =
      Conversation.apply(opened(), %Events.CaptureFailed{
        actor: @actor,
        at: @at,
        id: "r1-s1",
        session_key: "s1",
        turn_ref: "t9",
        reason: "spool"
      })

    resolve = %Commands.ResolveCaptureFailure{
      actor: @actor,
      at: @at,
      note: "lost it",
      id: "r1-s1",
      session_key: "s1",
      turn_ref: "t9",
      how: "marked_lost"
    }

    assert %Events.CaptureFailureResolved{how: "marked_lost"} =
             event = Conversation.execute(failed, resolve)

    assert {:error, :no_such_failure} =
             Conversation.execute(Conversation.apply(failed, event), resolve)

    assert {:error, :how_invalid} = Conversation.execute(failed, %{resolve | how: "shrugged"})

    # A later capture of the turn clears the failure too.
    captured = Conversation.apply(failed, Conversation.execute(failed, capture("t9")))
    assert {:error, :no_such_failure} = Conversation.execute(captured, resolve)
  end

  test "the turn key is the start instant and the hash of the messages' hashes" do
    assert {"2026-10-29T12:00:00.000000Z", digest} = Conversation.turn_key(@at, @messages)
    assert digest == :crypto.hash(:sha256, "h1\nh2") |> Base.encode16(case: :lower)
  end
end
