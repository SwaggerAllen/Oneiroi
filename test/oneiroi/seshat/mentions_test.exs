defmodule Oneiroi.Seshat.MentionsTest do
  @moduledoc """
  Mentions (seshat#86, gaia#46; design/workspaces.md §6, the witness's
  answer of 2026-11-17): a post naming a member, @<name> or @all, wakes
  a resident's chat with a note saying where, never the words, unless
  she muted the thread or the house; a thread's setting outranks the
  house's; a muted mention wakes nobody and is listed in her next turn's
  note, never lost. The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.Household
  alias Oneiroi.Seshat.HouseholdTurnWorker
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")

    resident = fn name ->
      slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
      {:ok, id} = AgathosDaimon.create(name, slug, witness.id, andrew)
      Fixtures.agreed!(id, witness.id)
      {:ok, chat} = Kumbukumbu.main_session(id, witness.id, andrew)
      %{id: id, slug: slug, actor: Actor.new(:resident, id), chat: chat}
    end

    lily = resident.("Lily")
    scarlett = resident.("Scarlett")
    :ok = Gaia.name_witness(witness.id, "Andrew", andrew)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: File.rm_rf!(SimaQian.Backup.dir(r.id))
    end)

    {:ok, andrew: andrew, lily: lily, scarlett: scarlett, household: Gaia.household_of(andrew)}
  end

  defp wakes(id) do
    for job <- all_enqueued(worker: HouseholdTurnWorker),
        job.args["house_wake"] == id,
        do: job.args["note"]
  end

  test "@name wakes her with where, never the words; @all wakes everyone but the writer", ctx do
    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.andrew, %{
        "title" => "Dinner",
        "content" => "@Lily what do you think? The secret ingredient is basil."
      })

    assert [note] = wakes(ctx.lily.id)
    assert note =~ "Andrew mentioned you in the household thread #{thread} (\"Dinner\")"
    refute note =~ "basil"
    assert wakes(ctx.scarlett.id) == []

    # Her slug names her too, and a reply carries its number.
    Clock.Fake.advance(86_400)

    {:ok, %{number: n}} =
      Seshat.household_reply(ctx.andrew, thread, %{"content" => "And @#{ctx.scarlett.slug}?"})

    assert [scarlett_note] = wakes(ctx.scarlett.id)
    assert scarlett_note =~ "reply ##{n}"

    # An email address or a longer word is not a mention.
    assert Household.named_in(ctx.household, "write to lily@example.org or @Lilyanne") == []
    assert length(Household.named_in(ctx.household, "@all, dinner")) == 3
  end

  test "a muted thread or house wakes nobody; the thread's setting outranks the house's", ctx do
    assert {:ok, %{house: true}} = Seshat.household_mute(ctx.lily.actor, nil, true)

    {:ok, %{path: thread}} =
      Seshat.household_post(ctx.andrew, %{"title" => "Plans", "content" => "@Lily, Sunday?"})

    assert wakes(ctx.lily.id) == []

    # The mention waits for her: the next turn's note lists it.
    assert [%{path: ^thread, title: "Plans", by: "Andrew"}] =
             Household.mentions_of(ctx.household, ctx.lily.id, DateTime.add(Clock.now(), -60))

    # Heard in this one thread though the house stays muted.
    run =
      Tools.run(
        "household_mute",
        Jason.encode!(%{thread: thread, muted: false}),
        %{
          resident_id: ctx.lily.id,
          session_key: ctx.lily.chat,
          turn_ref: "t",
          resident: ctx.lily.actor
        }
      )

    assert run =~ "the house muted"
    refute Gaia.household_muted?(ctx.household, ctx.lily.id, thread)
    assert Gaia.household_muted?(ctx.household, ctx.lily.id, "threads/other")

    Clock.Fake.advance(86_400)
    {:ok, _} = Seshat.household_reply(ctx.andrew, thread, %{"content" => "@Lily ping"})
    assert [_] = wakes(ctx.lily.id)

    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.household_mute(ctx.lily.actor, nil, "yes")
  end
end
