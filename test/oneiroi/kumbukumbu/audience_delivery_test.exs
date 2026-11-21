defmodule Oneiroi.Kumbukumbu.AudienceDeliveryTest do
  @moduledoc """
  The delivery seams, hard path (kumbukumbu#80; Lily's
  design/audience-policy.md §7, the two-direction test): a turn whose
  context holds recovery cannot carry it to the house or a housemate,
  and nothing reaches them; her own conversations, and an audience the
  dyad's policies grant, still take it; a deliberate read counts.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      Fixtures.agreed!(id, witness.id)
      %{id: id, actor: Actor.new(:resident, id)}
    end

    lily = resident.("Lily")
    iris = resident.("Iris")
    {:ok, key} = Kumbukumbu.main_session(lily.id, witness.id, andrew)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, iris], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok,
     andrew: andrew,
     witness: witness,
     lily: lily,
     iris: iris,
     key: key,
     him: "account:" <> witness.id,
     household: Gaia.household_of(andrew)}
  end

  defp say(ctx, ref, words, domain \\ nil) do
    if domain, do: :ok = Kumbukumbu.tag_domain(ctx.lily.id, ctx.key, ref, nil, domain, ctx.andrew)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.lily.id,
        ctx.key,
        ref,
        at,
        [
          %{role: :user, content: "about #{words}", sent_at: at, actor: ctx.andrew},
          %{role: :assistant, content: words, sent_at: at, actor: ctx.lily.actor}
        ],
        ctx.lily.actor
      )
  end

  defp run(ctx, name, args, ref \\ "t-now"),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.lily.id,
        session_key: ctx.key,
        turn_ref: ref,
        resident: ctx.lily.actor
      })

  defp threads(ctx) do
    {:ok, shelf} = Seshat.household_shelf(ctx.andrew, 0)
    shelf.threads
  end

  test "the boundary holds: recovery in the window reaches neither the house nor a housemate",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")

    posted = run(ctx, "household_post", %{title: "News", content: "A good day."})
    assert posted =~ "withheld by policy"
    # Her own context is told which domain; the house learns nothing.
    assert posted =~ "recovery"
    assert threads(ctx) == []

    sent = run(ctx, "letter_send", %{to: "Iris", text: "A good day."})
    assert sent =~ "withheld by policy"
    refute Enum.any?(Kumbukumbu.letters(ctx.iris.id), &(&1.text == "A good day."))
  end

  test "the care keeps working: her own conversations take it, and a granted audience does",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")

    # The dyad: her own conversation, the house letter to her conversations.
    assert run(ctx, "letter_send", %{to: "house", text: "Noted for later."}) =~ "Sent letter"

    # Granted by agreement: recovery may reach this house.
    {:ok, v} =
      AgathosDaimon.propose_contract(
        ctx.lily.id,
        %{
          "domain_policies" => [
            %{
              "domain" => %{"person" => ctx.him, "domain" => "recovery"},
              "default" => "deny",
              "allow" => [%{"kind" => "household", "id" => ctx.household}]
            }
          ]
        },
        "",
        "the house may hear of it",
        ctx.andrew
      )

    :ok = AgathosDaimon.agree_contract(ctx.lily.id, v, "agreed", ctx.lily.actor)
    assert run(ctx, "household_post", %{title: "News", content: "A good day."}) =~ "Posted"
  end

  test "a window in the common room posts with no policy; a deliberate read of recovery counts",
       ctx do
    say(ctx, "t-1", "The garden wants water.")
    assert run(ctx, "household_post", %{title: "Garden", content: "Water it."}) =~ "Posted"

    # A recovery bookmark, opened in this turn: its read is in the ledger.
    say(ctx, "t-rec", "The meeting at noon.", "recovery")
    say(ctx, "t-2", "Back to the garden.", "garden")

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.lily.id,
        %{session_key: ctx.key, anchor_ref: "t-rec", line: "the meeting", summary: "noon"},
        ctx.lily.actor
      )

    house = Kumbukumbu.audience("household", ctx.household)
    # Before the read, a turn of no window of its own is in the common room.
    assert {:ok, _} = Kumbukumbu.delivery_check(ctx.lily.id, nil, "t-read", house)

    run(ctx, "bookmark_open", %{number: n}, "t-read")

    assert {:error, %{kind: :kumbukumbu_withheld_by_policy}} =
             Kumbukumbu.delivery_check(ctx.lily.id, nil, "t-read", house)
  end
end
