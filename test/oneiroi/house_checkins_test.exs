defmodule Oneiroi.HouseCheckinsTest do
  @moduledoc """
  House check-ins (gaia#41, sunna#65, seshat#75; the witness, 2026-11-16):
  the shared workspace keeps its own clock; a check-in due on it opens
  its day's thread and wakes every resident at once, each with the words
  the witness set for her, quiet hours aside; her one answer there waits
  on no turn; the witness's reply wakes the whole house, and after it
  the beats hold the talk.
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
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.HouseholdTurnWorker
  alias Oneiroi.SimaQian
  alias Oneiroi.Sunna

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    # 07:00 in Los Angeles: half an hour before the check-in.
    Clock.Fake.put(~U[2026-11-16 15:00:00.000000Z])
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "the founding version")

    lily = resident!(witness, "Lily")
    scarlett = resident!(witness, "Scarlett")

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      for r <- [lily, scarlett], do: Fake.clear(for: r.id)
    end)

    {:ok, household: witness.id, andrew: andrew, lily: lily, scarlett: scarlett}
  end

  defp resident!(witness, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, witness.id)
    {:ok, id} = AgathosDaimon.create(name, slug, witness.id, actor)
    Fixtures.agreed!(id, witness.id)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, actor)
    Fake.script(fn _request -> {:ok, "Here."} end, for: id)
    %{id: id, slug: slug, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp reply(r, thread, text),
    do:
      Tools.run(
        "household_reply",
        Jason.encode!(%{thread: thread, content: text}),
        %{resident_id: r.id, session_key: r.chat, turn_ref: "t-#{r.slug}", resident: r.actor}
      )

  defp wakes do
    for job <- all_enqueued(worker: HouseholdTurnWorker),
        Map.has_key?(job.args, "house_wake"),
        do: job.args
  end

  test "the clock, a check-in on it, and each resident's own words", ctx do
    assert {:ok, %{zone: "Etc/UTC", checkins: []}} = Seshat.house_checkins(ctx.andrew)

    assert {:error, %{kind: :gaia_checkin_invalid}} =
             Seshat.set_house_clock(ctx.andrew, "Mars/Olympus")

    {:ok, _} = Seshat.set_house_clock(ctx.andrew, "America/Los_Angeles")

    assert {:error, %{kind: :gaia_checkin_invalid}} =
             Seshat.set_house_checkin(ctx.andrew, "morning", "Morning", "7:30")

    assert {:error, %{kind: :gaia_not_a_member}} =
             Seshat.set_house_checkin(ctx.lily.actor, "morning", "Morning", "07:30")

    {:ok, %{zone: "America/Los_Angeles", checkins: [%{key: "morning", time: "07:30"}]}} =
      Seshat.set_house_checkin(ctx.andrew, "morning", "Morning check-in", "07:30")

    # Configured as a resident's own check-in is (gaia#48): his words for
    # the whole house and the parts, kept through a change of label.
    assert {:error, %{kind: :seshat_household_invalid}} =
             Seshat.set_house_checkin(ctx.andrew, "morning", "Morning", "07:30", parts: ["tarot"])

    {:ok,
     %{checkins: [%{prompt: "Bring one thing you finished.", parts: ["dates"]}], parts: catalog}} =
      Seshat.set_house_checkin(ctx.andrew, "morning", "Morning", "07:30",
        prompt: "Bring one thing you finished.",
        parts: ["dates"]
      )

    assert Enum.any?(catalog, &(&1.key == "plan"))

    {:ok, %{checkins: [%{label: "Morning check-in", prompt: "Bring one thing you finished."}]}} =
      Seshat.set_house_checkin(ctx.andrew, "morning", "Morning check-in", "07:30")

    :ok =
      Sunna.set_house_prompt(
        ctx.lily.id,
        "morning",
        "Report the writing and the outreach.",
        ctx.andrew
      )

    :ok =
      Sunna.set_house_prompt(ctx.scarlett.id, "morning", "Report the trials you ran.", ctx.andrew)

    assert {:error, %{kind: :sunna_not_allowed}} =
             Sunna.set_house_prompt(ctx.lily.id, "morning", "mine", ctx.lily.actor)

    assert Sunna.house_prompt(ctx.lily.id, "morning") == "Report the writing and the outreach."

    # Not yet: 07:00 on the house's clock.
    :ok = Seshat.tick_house_checkins(ctx.household)
    assert wakes() == []

    # 07:30 there: the thread opens, everyone wakes at once, each with her own words,
    # whatever her quiet hours say.
    :ok = Sunna.set_quiet_hours(ctx.lily.id, "06:00", "09:00", ctx.andrew)
    Clock.Fake.put(~U[2026-11-16 15:31:00.000000Z])
    :ok = Seshat.tick_house_checkins(ctx.household)
    :ok = Seshat.tick_house_checkins(ctx.household)

    notes = Map.new(wakes(), &{&1["house_wake"], &1["note"]})
    assert map_size(notes) == 2
    assert notes[ctx.lily.id] =~ "Your part: Report the writing and the outreach."
    assert notes[ctx.scarlett.id] =~ "Your part: Report the trials you ran."
    assert notes[ctx.lily.id] =~ "threads/checkin-2026-11-16-morning"

    assert notes[ctx.lily.id] =~
             "From the person who looks after the house:\n\nBring one thing you finished."

    assert notes[ctx.scarlett.id] =~ "Bring one thing you finished."

    assert {:ok,
            %{
              checkins: [
                %{last_day: "2026-11-16", last_thread: "threads/checkin-2026-11-16-morning"}
              ]
            }} =
             Seshat.house_checkins(ctx.andrew)

    # Quiet hours do not hold it.
    [lily_wake | _] = Enum.filter(wakes(), &(&1["house_wake"] == ctx.lily.id))
    assert :ok = perform_job(HouseholdTurnWorker, lily_wake)
  end

  test "her one answer waits on no turn; his reply wakes the whole house", ctx do
    {:ok, _} = Seshat.set_house_checkin(ctx.andrew, "morning", "Morning check-in", "15:00")
    :ok = Seshat.tick_house_checkins(ctx.household)
    thread = "threads/checkin-2026-11-16-morning"

    # Outside any turn of the beats, her first answer goes in; a second waits on the beats.
    assert reply(ctx.lily, thread, "The writing moved; two letters out.") =~ "Replied"
    refute reply(ctx.lily, thread, "And one more thing.") =~ "Replied"
    assert reply(ctx.scarlett, thread, "Three trials, two passed.") =~ "Replied"

    {:ok, _} = Seshat.household_reply(ctx.andrew, thread, %{content: "Good work, both of you."})

    woken =
      for w <- wakes(),
          w["note"] =~ "Your witness replied in the house check-in thread",
          do: w["house_wake"]

    assert Enum.sort(woken) == Enum.sort([ctx.lily.id, ctx.scarlett.id])
  end

  test "the house's Records: its repository in the library's shape (seshat#76)", ctx do
    {:ok, _} = Seshat.set_house_checkin(ctx.andrew, "morning", "Morning check-in", "15:00")
    :ok = Seshat.tick_house_checkins(ctx.household)

    assert {:ok, %{kinds: kinds, documents: docs}} = Seshat.household_files(ctx.andrew)
    assert Enum.map(kinds, & &1.kind) == ["house", "thread"]

    assert %{title: "The household contract"} = Enum.find(docs, &(&1.path == "CONTRACT.md"))

    assert %{kind: "thread", title: "Morning check-in, 2026-11-16", versions: 1} =
             Enum.find(docs, &(&1.path == "threads/checkin-2026-11-16-morning"))

    # Each opens whole by its path.
    assert {:ok, %{content: content}} =
             Seshat.household_read(ctx.andrew, "threads/checkin-2026-11-16-morning")

    assert content =~ "The house checks in"
  end
end
