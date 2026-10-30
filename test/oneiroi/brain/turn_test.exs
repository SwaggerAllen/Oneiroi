defmodule Oneiroi.Brain.TurnTest do
  @moduledoc "A turn through the brain on the fake provider: captured, recorded, streamed; the three endings."
  use Oneiroi.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", Actor.new(:witness, witness.id))
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, Actor.new(:witness, witness.id))
    Fake.clear()
    :ok = PubSub.subscribe(:brain, :session)
    {:ok, witness: witness, resident: resident, key: key, actor: Actor.new(:witness, witness.id)}
  end

  test "the capacity alarm flags the turn when the always-loaded prefix nears the window", ctx do
    id = ctx.resident.id
    big = String.duplicate("I am Lily and the garden is mine. ", 1_700)
    assert byte_size(big) < 64_000
    :ok = AgathosDaimon.write_file(id, "SOUL.md", big, %{origin: "authored"}, ctx.actor)
    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "hello", ctx.actor)

    assert [%{label: "capacity", tokens: tokens, reason: reason}] =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(ref)
             |> Enum.filter(&(&1.label == "capacity"))

    assert tokens > 14_400
    assert reason =~ "of a 16000-token window"
    assert reason =~ "90% alarm"
  end

  test "the near-miss record: the bookmarks the index ranked and did not inject, with their reasons, and never counted as indexed",
       ctx do
    id = ctx.resident.id
    resident = Actor.new(:resident, id, "fake/model")
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        ctx.key,
        "anchor",
        at,
        [%{role: :user, content: "a moment", sent_at: at, actor: ctx.actor}],
        resident
      )

    for n <- 1..60 do
      attrs = %{
        session_key: ctx.key,
        anchor_ref: "anchor",
        line: "bookmark number #{n} " <> String.duplicate("word ", 16),
        summary: "the #{n}th"
      }

      {:ok, ^n} = Kumbukumbu.add_bookmark(id, attrs, resident)
    end

    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "hello", ctx.actor)
    rows = Kumbukumbu.injections({:account, ctx.witness.id}, ref)
    [index] = Enum.filter(rows, &(&1.label == "index"))
    misses = Enum.filter(rows, &(&1.label == "near-miss"))
    assert misses != []
    assert index.reason =~ "#{length(misses)} left out"
    assert Enum.all?(misses, &(&1.tokens == 0 and &1.reason =~ "considered and not injected"))
    assert Enum.all?(misses, &(&1.text =~ "bookmark number"))

    # A near-miss is not in the index text and its row was never marked as indexed.
    [miss | _] = misses
    [number] = Regex.run(~r/bookmark #(\d+)/, miss.reason, capture: :all_but_first)
    refute index.text =~ miss.text

    assert {:ok, %{last_indexed_at: nil}, _span} =
             Kumbukumbu.bookmark(id, String.to_integer(number))
  end

  defp events(resident_id, key) do
    receive do
      {:oneiroi, _topic, {^resident_id, ^key, payload}, _trace} ->
        [payload | events(resident_id, key)]
    after
      0 -> []
    end
  end

  test "a turn is answered, captured as user and assistant, recorded, and streamed", ctx do
    assert {:ok, %{turn_ref: ref, messages: [user, reply], drew_on: 4}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello there", ctx.actor)

    assert user.role == :user and user.actor.kind == :witness
    assert reply.role == :assistant and reply.content == "The fake provider heard: hello there"
    assert reply.actor.kind == :resident and reply.actor.model == "fake/model"

    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert ["user", "assistant"] = Enum.map(messages, & &1.role)

    assert [
             %{label: "prompt"},
             %{label: "AGENTS.md"},
             %{label: "index"},
             %{label: "transcript", tokens: 0}
           ] =
             Kumbukumbu.injections({:account, ctx.witness.id}, ref)

    assert [%{calls: 1}] =
             Nisaba.spend(ctx.resident.id, :witness, :purpose, ~U[2026-10-01 00:00:00.000000Z])

    payloads = events(ctx.resident.id, ctx.key)
    assert {:turn_started, ^ref} = hd(payloads)
    assert Enum.any?(payloads, &match?({:delta, ^ref, _}, &1))
    assert {:turn, ^ref, %{drew_on: 4}} = List.last(payloads)
  end

  test "the next turn is shown the transcript so far, and the fake answers the last user message",
       ctx do
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "first", ctx.actor)

    assert {:ok, %{turn_ref: ref}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "second", ctx.actor)

    assert [_, _, _, %{label: "transcript", tokens: tokens}] =
             Kumbukumbu.injections({:account, ctx.witness.id}, ref)

    assert tokens > 0
  end

  test "a refusal is an ordinary captured turn in the resident's words", ctx do
    Fake.refuse("I would rather not.", for: ctx.resident.id)

    assert {:ok, %{messages: [_, %{refusal: true, content: "I would rather not."}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "do it", ctx.actor)

    {:ok, _s, [_, reply]} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert reply.refusal and reply.role == "assistant"
    assert [] = Kumbukumbu.failures({:account, ctx.witness.id})
  end

  test "a budget stop captures the message and an honest notice both parties read", ctx do
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 1, :month, ctx.actor)
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "one", ctx.actor)

    assert {:error, {%Nisaba.Error{kind: :nisaba_budget_exceeded}, %{messages: [_, notice]}}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "two", ctx.actor)

    assert notice.role == :system and notice.content =~ "budget line for chat is spent"
    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert ["user", "assistant", "user", "system"] = Enum.map(messages, & &1.role)
  end

  test "a provider failure captures nothing and records a capture failure", ctx do
    Fake.fail(:transport, for: ctx.resident.id)

    assert {:error, %Oneiroi.Brain.Error{kind: :brain_turn_failed}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello", ctx.actor)

    assert {:ok, _s, []} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert [%{reason: "nisaba_provider_failed"}] = Kumbukumbu.failures({:account, ctx.witness.id})
    assert Enum.any?(events(ctx.resident.id, ctx.key), &match?({:failed, _, _}, &1))
  end

  test "two turns on one session run one at a time on its process", ctx do
    parent = self()

    tasks =
      for text <- ["a", "b"] do
        Task.async(fn ->
          Sandbox.allow(Oneiroi.Repo, parent, self())
          Oneiroi.Brain.turn(ctx.resident.id, ctx.key, text, ctx.actor)
        end)
      end

    assert [{:ok, _}, {:ok, _}] = Task.await_many(tasks, 30_000)
    {:ok, s, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert s.turns == 2 and length(messages) == 4
    assert ["user", "assistant", "user", "assistant"] = Enum.map(messages, & &1.role)
  end
end
