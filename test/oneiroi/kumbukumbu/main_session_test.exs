defmodule Oneiroi.Kumbukumbu.MainSessionTest do
  @moduledoc """
  The Oneiroi chat stays the Oneiroi chat (kumbukumbu #40): the main
  session is the platform's own conversation with the witness, the
  oldest the brain opened, and a session an adapter opens, Claude Code's
  included, can never become it, however new it is.
  """
  use Oneiroi.DataCase, async: false

  alias Commanded.Event.Upcaster
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    {:ok, witness: witness, resident: resident, actor: Actor.new(:witness, witness.id)}
  end

  # The regression: before kumbukumbu #40 the newest session of kind
  # `main` was the chat, and an adapter's session opened as `main` was
  # the newest the moment it opened, so the witness's next message landed
  # in the Claude Code conversation and the platform's brain answered
  # there.
  test "the witness's main session stays the brain's after an adapter session opens", ctx do
    id = ctx.resident.id
    {:ok, chat} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)
    # Later, as in production: under one fixed instant the two sessions
    # tie on `opened_at` and the order is whatever Postgres returns.
    Clock.Fake.advance(60)

    {:ok, claude} =
      Kumbukumbu.open_session(
        id,
        "main",
        "claude-code",
        [ctx.witness.id],
        Actor.new(:resident, id)
      )

    refute claude == chat
    assert {:ok, ^chat} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)

    # Asked for as `main` through another adapter, it is the adapter's
    # kind: the chat's kind is the platform's alone.
    assert {:ok, %{kind: "adapter"}, []} = Kumbukumbu.transcript({:resident, id}, claude)
  end

  test "the main session is the oldest of the platform's, whatever order the rows come back in",
       ctx do
    id = ctx.resident.id
    {:ok, first} = Kumbukumbu.open_session(id, "main", "brain", [ctx.witness.id], ctx.actor)
    Clock.Fake.advance(60)
    {:ok, _second} = Kumbukumbu.open_session(id, "main", "brain", [ctx.witness.id], ctx.actor)

    assert {:ok, ^first} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)
  end

  test "an adapter's conversation is kind adapter, by its folder's base name, and a client cannot open the kind",
       ctx do
    id = ctx.resident.id
    brain = Actor.new(:resident, id)

    {:ok, key} =
      Kumbukumbu.open_adapter(id, "laptop", [ctx.witness.id], brain,
        label: "/home/allen/src/Oneiroi/",
        runtime: "claude-code"
      )

    assert {:ok, %{kind: "adapter", label: "Oneiroi", runtime: "claude-code"}, []} =
             Kumbukumbu.transcript({:resident, id}, key)

    # A second open is a second conversation, never the first found again.
    {:ok, other} = Kumbukumbu.open_adapter(id, "laptop", [ctx.witness.id], brain, [])
    refute other == key

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_kind_invalid}} =
             Kumbukumbu.open_session(id, "adapter", "brain", [ctx.witness.id], ctx.actor)
  end

  test "a folder is called by its base name alone" do
    assert Kumbukumbu.folder_label("/Users/allen/work/catapult") == "catapult"
    assert Kumbukumbu.folder_label("C:\\Users\\allen\\Oneiroi\\") == "Oneiroi"
    assert Kumbukumbu.folder_label("Oneiroi") == "Oneiroi"
    assert Kumbukumbu.folder_label("/") == nil
    assert Kumbukumbu.folder_label("/tmp/..") == nil
    assert Kumbukumbu.folder_label(nil) == nil

    assert Kumbukumbu.folder_label("/x/" <> String.duplicate("a", 100)) ==
             String.duplicate("a", 64)
  end

  test "a SessionOpened an adapter wrote as main before the kind reads back as the adapter's" do
    v2 = %Oneiroi.Kumbukumbu.Events.SessionOpened{
      actor: Actor.new(:resident, "r"),
      at: Clock.now(),
      kind: "main",
      adapter: "claude-code",
      participants: [],
      session_key: "k",
      resident_id: "r"
    }

    assert %{kind: "adapter", label: nil, runtime: nil} = Upcaster.upcast(v2, %{})
    assert %{kind: "main"} = Upcaster.upcast(%{v2 | adapter: "brain"}, %{})
    assert %{kind: "free_time"} = Upcaster.upcast(%{v2 | kind: "free_time"}, %{})
  end

  test "a tool call's turn is the open turn it names, else the newest, and the count it chose among",
       ctx do
    id = ctx.resident.id
    brain = Actor.new(:resident, id)
    assert %{rule: :none, turn_ref: nil, open: 0} = Kumbukumbu.attribute(id, "laptop", nil)

    {:ok, a} = Kumbukumbu.open_adapter(id, "laptop", [ctx.witness.id], brain, label: "a")
    {:ok, b} = Kumbukumbu.open_adapter(id, "laptop", [ctx.witness.id], brain, label: "b")
    :ok = Kumbukumbu.start_turn(id, a, "ta", brain)
    Clock.Fake.advance(1)
    :ok = Kumbukumbu.start_turn(id, b, "tb", brain)

    assert %{session_key: ^a, turn_ref: "ta", rule: :named, open: 2} =
             Kumbukumbu.attribute(id, "laptop", "ta")

    assert %{session_key: ^b, turn_ref: "tb", rule: :newest, label: "b"} =
             Kumbukumbu.attribute(id, "laptop", nil)

    # Another adapter's open turn is never this one's to name.
    assert %{rule: :none} = Kumbukumbu.attribute(id, "phone", "ta")

    # Open now: both in flight, newest first, and the chat just opened.
    Clock.Fake.advance(1)
    {:ok, chat} = Kumbukumbu.main_session(id, ctx.witness.id, ctx.actor)

    assert [%{key: ^chat, kind: "main"}, %{key: ^b, in_flight: true}, %{key: ^a, label: "a"}] =
             Kumbukumbu.open_now(id)

    # Past the window a conversation with nothing in flight is not open.
    Clock.Fake.advance(31 * 60)
    assert [%{key: ^b}, %{key: ^a}] = Kumbukumbu.open_now(id)
    assert %{} == Kumbukumbu.drew_on({:resident, id}, a)
  end
end
