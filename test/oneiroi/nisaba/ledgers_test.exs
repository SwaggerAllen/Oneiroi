defmodule Oneiroi.Nisaba.LedgersTest do
  @moduledoc """
  The ledger through its exports, against the real store and the fake
  provider: a metered call records what it cost, a cap stops the next
  call and says so once, and the resident's own view never shows the
  purposes the unawareness invariant hides.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.{Fake, Request, Result}

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", Actor.new(:steward, steward.id))
    Fake.clear()
    {:ok, steward: steward, resident: resident, actor: Actor.new(:resident, resident.id)}
  end

  defp request, do: Request.new("fake/model", [%{role: :user, content: "hello there friend"}])

  test "a metered call answers, records the call with its cost, and the ledger shows it", ctx do
    assert {:ok, %Result{content: "The fake provider heard: hello there friend"} = r} =
             Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    [chat | _] = Nisaba.budgets(ctx.resident.id, :steward)
    assert chat.purpose == :chat and chat.cap_nanos == nil and chat.period == :month
    assert chat.spent_nanos == r.usage.cost_nanos

    since = ~U[2026-10-01 00:00:00.000000Z]

    assert [%{key: "chat", calls: 1, cost_nanos: cost}] =
             Nisaba.spend(ctx.resident.id, :steward, :purpose, since)

    assert cost == r.usage.cost_nanos

    assert [%{key: "fake/model", calls: 1}] =
             Nisaba.spend(ctx.resident.id, :steward, :model, since)

    assert [%{key: "resident:" <> _, calls: 1}] =
             Nisaba.spend(ctx.resident.id, :steward, :actor, since)
  end

  test "a cap stops the call that would follow the one that crossed it, and the line says it is exceeded",
       ctx do
    # The fake prices 10 tokens at 1,000 nanos each: one call costs 10,000.
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 15_000, :month, ctx.actor)
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    assert {:error, %Nisaba.Error{kind: :nisaba_budget_exceeded}} =
             Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    [chat | _] = Nisaba.budgets(ctx.resident.id, :steward)
    assert chat.exceeded and chat.spent_nanos == 20_000 and chat.cap_nanos == 15_000

    # Another purpose is another line.
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :judge, request(), ctx.actor)

    # Raising the line lets the next call through and clears the stop.
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 100_000, :month, ctx.actor)
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)
    [chat | _] = Nisaba.budgets(ctx.resident.id, :steward)
    refute chat.exceeded
  end

  test "a spent line opens again when its period turns", ctx do
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 10_000, :day, ctx.actor)
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    assert {:error, %Nisaba.Error{kind: :nisaba_budget_exceeded}} =
             Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    Oneiroi.Apsu.Clock.Fake.advance(24 * 3600)
    [chat | _] = Nisaba.budgets(ctx.resident.id, :steward)
    assert chat.spent_nanos == 0 and not chat.exceeded
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)
  end

  test "the resident's view omits drafting and regression, in the lines and in the spend", ctx do
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :regression, request(), ctx.actor)
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :drafting, request(), ctx.actor)
    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    steward = Nisaba.budgets(ctx.resident.id, :steward) |> Enum.map(& &1.purpose)
    resident = Nisaba.budgets(ctx.resident.id, :resident) |> Enum.map(& &1.purpose)
    assert :regression in steward and :drafting in steward
    refute :regression in resident or :drafting in resident

    since = ~U[2026-10-01 00:00:00.000000Z]

    assert ["chat", "drafting", "regression"] =
             Nisaba.spend(ctx.resident.id, :steward, :purpose, since) |> Enum.map(& &1.key)

    assert ["chat"] =
             Nisaba.spend(ctx.resident.id, :resident, :purpose, since) |> Enum.map(& &1.key)

    assert [%{calls: 1}] = Nisaba.spend(ctx.resident.id, :resident, :model, since)
  end

  test "no key, an unknown purpose and a provider failure are each named, and none is recorded",
       ctx do
    assert {:error, %Nisaba.Error{kind: :nisaba_unknown_purpose}} =
             Nisaba.call(ctx.resident.id, :bribes, request(), ctx.actor)

    Fake.fail(:transport)

    assert {:error, %Nisaba.Error{kind: :nisaba_provider_failed}} =
             Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    Fake.fail(:schema_invalid)

    assert {:error, %Nisaba.Error{kind: :nisaba_request_refused}} =
             Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    Fake.clear()

    :ok = Oneiroi.Gaia.revoke_key(ctx.steward.id, Actor.new(:steward, ctx.steward.id))
    assert {:error, :gaia_no_key} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    assert [] = Nisaba.spend(ctx.resident.id, :steward, :purpose, ~U[2026-10-01 00:00:00.000000Z])
  end

  test "a refusal is an ordinary, recorded result in the model's words", ctx do
    Fake.refuse("I would rather not say.")

    assert {:ok, %Result{refusal?: true, content: "I would rather not say."}} =
             Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    assert [%{calls: 1}] =
             Nisaba.spend(ctx.resident.id, :steward, :purpose, ~U[2026-10-01 00:00:00.000000Z])
  end

  test "streaming delivers the deltas and records like a call", ctx do
    parent = self()
    Fake.reply("a b")

    assert {:ok, %Result{content: "a b"}} =
             Nisaba.stream(
               ctx.resident.id,
               :chat,
               request(),
               ctx.actor,
               &send(parent, {:delta, &1})
             )

    assert_received {:delta, "a "}
    assert_received {:delta, "b"}

    assert [%{calls: 1}] =
             Nisaba.spend(ctx.resident.id, :steward, :purpose, ~U[2026-10-01 00:00:00.000000Z])
  end

  test "two residents' ledgers never bleed, and a line is the resident's own", ctx do
    other_steward = Fixtures.account!()
    other = Fixtures.resident!(other_steward)

    :ok =
      Oneiroi.Gaia.store_key(
        other_steward.id,
        "sk-or-other",
        Actor.new(:steward, other_steward.id)
      )

    :ok = Nisaba.set_budget(other.id, :chat, 5, :day, Actor.new(:resident, other.id))

    assert {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)
    assert {:ok, _} = Nisaba.call(other.id, :chat, request(), Actor.new(:resident, other.id))

    [mine | _] = Nisaba.budgets(ctx.resident.id, :steward)
    [theirs | _] = Nisaba.budgets(other.id, :steward)
    assert mine.cap_nanos == nil and theirs.cap_nanos == 5

    assert [%{calls: 1}] =
             Nisaba.spend(ctx.resident.id, :steward, :purpose, ~U[2026-10-01 00:00:00.000000Z])

    assert [%{calls: 1}] =
             Nisaba.spend(other.id, :steward, :purpose, ~U[2026-10-01 00:00:00.000000Z])
  end

  test "the cost of a call and of the ledger read does not grow with the usage table", ctx do
    :ok = Nisaba.set_budget(ctx.resident.id, :chat, 1_000_000_000, :month, ctx.actor)
    for _ <- 1..3, do: {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    # Scoped transactions for the steward, the key and the line with its
    # period's sum, and nothing else from this process (the record is the
    # projector's, in its own process); the sum is an index range. The
    # count is a constant, so it is measured against itself after thirty
    # more rows rather than against a number somebody guessed.
    {_result, calls_before} =
      count_statements(fn ->
        {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)
      end)

    {_result, read_before} = count_statements(fn -> Nisaba.budgets(ctx.resident.id, :steward) end)

    for _ <- 1..30, do: {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)

    {_result, calls_after} =
      count_statements(fn ->
        {:ok, _} = Nisaba.call(ctx.resident.id, :chat, request(), ctx.actor)
      end)

    {_result, read_after} = count_statements(fn -> Nisaba.budgets(ctx.resident.id, :steward) end)

    assert calls_after == calls_before
    assert read_after == read_before
    assert calls_before <= 20
  end
end
