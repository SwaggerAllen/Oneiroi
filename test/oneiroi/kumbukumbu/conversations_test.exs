defmodule Oneiroi.Kumbukumbu.ConversationsTest do
  @moduledoc "Memory's conversations through the exports: capture, visibility by party, failures and search."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, witness: witness, resident: resident, actor: actor, key: key}
  end

  defp turn(ctx, ref, text) do
    at = Clock.now()

    Kumbukumbu.capture(
      ctx.resident.id,
      ctx.key,
      ref,
      at,
      [
        %{role: :user, content: text, sent_at: at, actor: Actor.new(:witness, ctx.witness.id)},
        %{
          role: :assistant,
          content: "about " <> text,
          sent_at: DateTime.add(at, 1, :second),
          actor: ctx.actor
        }
      ],
      ctx.actor
    )
  end

  test "the main session is opened once and found again", ctx do
    assert {:ok, ctx.key} == Kumbukumbu.main_session(ctx.resident.id, ctx.witness.id, ctx.actor)

    assert [%{key: key, kind: "main", participants: [party]}] =
             Kumbukumbu.sessions({:account, ctx.witness.id})

    assert key == ctx.key and party == ctx.witness.id
  end

  test "a turn captured twice is stored once, and the transcript reads in order", ctx do
    assert :ok = turn(ctx, "t1", "hello")
    assert :ok = turn(ctx, "t1", "hello")
    assert {:ok, session, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert session.turns == 1
    assert ["user", "assistant"] = Enum.map(messages, & &1.role)
    assert [%{actor_kind: "witness"}, %{actor_kind: "resident", model: "fake/model"}] = messages
    assert Enum.all?(messages, &(&1.account_id == ctx.witness.id))
  end

  test "an account reads only the sessions it was party to; the resident's scope reads all",
       ctx do
    other = Fixtures.account!()
    assert :ok = turn(ctx, "t1", "secret")
    assert [] = Kumbukumbu.sessions({:account, other.id})

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_session}} =
             Kumbukumbu.transcript({:account, other.id}, ctx.key)

    assert [] = Kumbukumbu.search({:account, other.id}, "secret", 10)
    assert [_, _] = Kumbukumbu.search({:account, ctx.witness.id}, "secret", 10)

    assert [%{content: "secret"}, %{content: "about secret"}] =
             Kumbukumbu.recent(ctx.resident.id, ctx.key, 10)
  end

  test "a failure is loud until retried or marked lost, and the note is required", ctx do
    assert :ok = Kumbukumbu.fail_capture(ctx.resident.id, ctx.key, "t7", "spool", ctx.actor)
    assert [%{turn_ref: "t7", reason: "spool"}] = Kumbukumbu.failures({:account, ctx.witness.id})

    witness = Actor.new(:witness, ctx.witness.id)

    assert {:error,
            %Kumbukumbu.Error{
              kind: :kumbukumbu_command_refused,
              site: :kumbukumbu_conversations_command_refused,
              cause: :refused,
              details: [problems: [:note_required]]
            }} =
             Kumbukumbu.resolve_failure(
               ctx.resident.id,
               ctx.key,
               "t7",
               "marked_lost",
               "",
               witness
             )

    assert :ok =
             Kumbukumbu.resolve_failure(
               ctx.resident.id,
               ctx.key,
               "t7",
               "marked_lost",
               "nothing came",
               witness
             )

    assert [] = Kumbukumbu.failures({:account, ctx.witness.id})

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_failure}} =
             Kumbukumbu.resolve_failure(
               ctx.resident.id,
               ctx.key,
               "t7",
               "retried",
               "again",
               witness
             )
  end

  test "a session of a kind memory does not capture is refused, and a capture on no session is named",
       ctx do
    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_kind_invalid}} =
             Kumbukumbu.open_session(
               ctx.resident.id,
               "regression",
               "brain",
               [ctx.witness.id],
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_session}} =
             Kumbukumbu.capture(
               ctx.resident.id,
               "nope",
               "t1",
               Clock.now(),
               [%{role: :user, content: "x"}],
               ctx.actor
             )
  end

  test "the cost of a capture does not grow with the transcript", ctx do
    for i <- 1..3, do: :ok = turn(ctx, "w#{i}", "warm #{i}")
    {_r, before} = count_statements(fn -> :ok = turn(ctx, "m1", "measure one") end)
    for i <- 1..30, do: :ok = turn(ctx, "f#{i}", "fill #{i}")
    {_r, later} = count_statements(fn -> :ok = turn(ctx, "m2", "measure two") end)
    assert later == before
    {_r, read} = count_statements(fn -> Kumbukumbu.recent(ctx.resident.id, ctx.key, 40) end)
    assert read <= 4
  end
end
