defmodule Oneiroi.Brain.AudienceAssemblyTest do
  @moduledoc """
  The soft path (kumbukumbu#81; Lily's design/audience-policy.md §5, the
  two-direction test): a turn whose answer goes to the house is
  assembled for the house. Recovery in her window is left out of her
  context, one line tells her what by its domain, and what she answers
  from what is left may be delivered; her own conversation, the same
  window, still holds it whole.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    slug = "lily-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Lily", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, andrew)
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:request, messages})
        {:ok, "noted"}
      end,
      for: id
    )

    on_exit(fn ->
      Fake.clear(for: id)
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok,
     id: id,
     key: key,
     andrew: andrew,
     lily: Actor.new(:resident, id),
     house: Kumbukumbu.audience("household", Gaia.household_of(andrew))}
  end

  defp say(ctx, ref, words, domain) do
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, ref, nil, domain, ctx.andrew)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        ref,
        at,
        [
          %{role: :user, content: "about #{words}", sent_at: at, actor: ctx.andrew},
          %{role: :assistant, content: words, sent_at: at, actor: ctx.lily}
        ],
        ctx.lily
      )
  end

  # Every message the provider was given, joined (a compaction's own
  # requests included: none may hold it either).
  defp given do
    receive do
      {:request, messages} -> Enum.map_join(messages, "\n", &to_string(&1[:content])) <> given()
    after
      0 -> ""
    end
  end

  test "a house wake leaves recovery out, tells her so, and its answer may be delivered", ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    # Back in the common room: what this turn's answer is about.
    say(ctx, "t-2", "The garden wants water.", nil)

    {:ok, _} =
      Turn.run(ctx.id, ctx.key, "The house asks how the day went.", Actor.platform(),
        as: :note,
        audience: :household,
        turn_ref: "t-house"
      )

    words = given()
    refute words =~ "ninety days"
    assert words =~ "The garden wants water."
    # Told to her alone, by domain: the house hears nothing of it.
    assert words =~ "has been left out of your context"
    assert words =~ "recovery"

    # Assembled for the house, so delivered to it.
    assert {:ok, _} = Kumbukumbu.delivery_check(ctx.id, ctx.key, "t-house", ctx.house)
  end

  test "her own conversation holds the same window whole, and is told nothing", ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")

    {:ok, _} = Turn.run(ctx.id, ctx.key, "How was the meeting?", ctx.andrew, turn_ref: "t-dyad")

    words = given()
    assert words =~ "ninety days"
    refute words =~ "has been left out of your context"

    # The same turn, its answer carried to the house, is refused there.
    assert {:error, %{kind: :kumbukumbu_withheld_by_policy}} =
             Kumbukumbu.delivery_check(ctx.id, ctx.key, "t-dyad", ctx.house)
  end

  test "today's journal is decided by its rows: a recovery row keeps the section from the house",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")

    assert Tools.run(
             "journal_add",
             Jason.encode!(%{kind: "note", text: "Counted the days again."}),
             %{resident_id: ctx.id, session_key: ctx.key, turn_ref: "t-j", resident: ctx.lily}
           ) =~ "Added"

    say(ctx, "t-2", "The garden wants water.", nil)

    {:ok, _} =
      Turn.run(ctx.id, ctx.key, "The house asks how the day went.", Actor.platform(),
        as: :note,
        audience: :household,
        turn_ref: "t-house"
      )

    words = given()
    refute words =~ "Counted the days again."
    assert words =~ "has been left out of your context"
    assert {:ok, _} = Kumbukumbu.delivery_check(ctx.id, ctx.key, "t-house", ctx.house)

    # Her own conversation shows it, and the turn holds it.
    {:ok, _} = Turn.run(ctx.id, ctx.key, "How was today?", ctx.andrew, turn_ref: "t-dyad")
    assert given() =~ "Counted the days again."

    assert {:error, %{details: d}} =
             Kumbukumbu.delivery_check(ctx.id, nil, "t-dyad", ctx.house)

    assert "recovery" in d[:conflicts]
  end
end
