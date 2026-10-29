defmodule Oneiroi.Brain.TurnTest do
  @moduledoc "A turn through the brain on the fake provider: captured, recorded, streamed; the three endings."
  use Oneiroi.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", Actor.new(:steward, steward.id))
    {:ok, key} = Kumbukumbu.main_session(resident.id, steward.id, Actor.new(:steward, steward.id))
    Fake.clear()
    :ok = PubSub.subscribe(:brain, :session)
    {:ok, steward: steward, resident: resident, key: key, actor: Actor.new(:steward, steward.id)}
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
    assert {:ok, %{turn_ref: ref, messages: [user, reply], drew_on: 3}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello there", ctx.actor)

    assert user.role == :user and user.actor.kind == :steward
    assert reply.role == :assistant and reply.content == "The fake provider heard: hello there"
    assert reply.actor.kind == :resident and reply.actor.model == "fake/model"

    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.steward.id}, ctx.key)
    assert ["user", "assistant"] = Enum.map(messages, & &1.role)

    assert [%{label: "prompt"}, %{label: "index"}, %{label: "transcript", tokens: 0}] =
             Kumbukumbu.injections({:account, ctx.steward.id}, ref)

    assert [%{calls: 1}] =
             Nisaba.spend(ctx.resident.id, :steward, :purpose, ~U[2026-10-01 00:00:00.000000Z])

    payloads = events(ctx.resident.id, ctx.key)
    assert {:turn_started, ^ref} = hd(payloads)
    assert Enum.any?(payloads, &match?({:delta, ^ref, _}, &1))
    assert {:turn, ^ref, %{drew_on: 3}} = List.last(payloads)
  end

  test "the next turn is shown the transcript so far, and the fake answers the last user message",
       ctx do
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "first", ctx.actor)

    assert {:ok, %{turn_ref: ref}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "second", ctx.actor)

    assert [_, _, %{label: "transcript", tokens: tokens}] =
             Kumbukumbu.injections({:account, ctx.steward.id}, ref)

    assert tokens > 0
  end

  test "a refusal is an ordinary captured turn in the resident's words", ctx do
    Fake.refuse("I would rather not.", for: ctx.resident.id)

    assert {:ok, %{messages: [_, %{refusal: true, content: "I would rather not."}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "do it", ctx.actor)

    {:ok, _s, [_, reply]} = Kumbukumbu.transcript({:account, ctx.steward.id}, ctx.key)
    assert reply.refusal and reply.role == "assistant"
    assert [] = Kumbukumbu.failures({:account, ctx.steward.id})
  end

  test "a budget stop captures the message and an honest notice both parties read", ctx do
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 1, :month, ctx.actor)
    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "one", ctx.actor)

    assert {:error, {%Nisaba.Error{kind: :nisaba_budget_exceeded}, %{messages: [_, notice]}}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "two", ctx.actor)

    assert notice.role == :system and notice.content =~ "budget line for chat is spent"
    {:ok, _s, messages} = Kumbukumbu.transcript({:account, ctx.steward.id}, ctx.key)
    assert ["user", "assistant", "user", "system"] = Enum.map(messages, & &1.role)
  end

  test "a provider failure captures nothing and records a capture failure", ctx do
    Fake.fail(:transport, for: ctx.resident.id)

    assert {:error, %Oneiroi.Brain.Error{kind: :brain_turn_failed}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "hello", ctx.actor)

    assert {:ok, _s, []} = Kumbukumbu.transcript({:account, ctx.steward.id}, ctx.key)
    assert [%{reason: "nisaba_provider_failed"}] = Kumbukumbu.failures({:account, ctx.steward.id})
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
    {:ok, s, messages} = Kumbukumbu.transcript({:account, ctx.steward.id}, ctx.key)
    assert s.turns == 2 and length(messages) == 4
    assert ["user", "assistant", "user", "assistant"] = Enum.map(messages, & &1.role)
  end
end
