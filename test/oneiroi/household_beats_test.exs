defmodule Oneiroi.HouseholdBeatsTest do
  @moduledoc """
  The household's beats (gaia#33 to #38, seshat#67 to #72, sunna#51,
  brain#84), end to end on one witness and three residents, the
  in-memory provider and the faked clock: always on from the household's
  creation on the default shape, with its phase; a ballot changing the
  shape (and refused when it would take the beats away); registration;
  turns fired by the minute from the sign-up's close, starved-first, one
  after another as each wake ends, up to the cap; a registration for one
  beat, any beat to come, ending with it, its miss banked so she goes
  first next beat; the turn's window (once in each thread, once to each
  document); writes outside a turn refused, votes allowed anytime and
  never counted; the post quota, for a resident and for the witness; the
  witness's one post per thread per beat, which fires no turn; the wake
  profiles; a timed-out turn moving the beat on as a miss; and the
  minimum share, nobody repeating while a registrant waits.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.HouseholdBallotWorker
  alias Oneiroi.Seshat.HouseholdTurnWorker
  alias Oneiroi.SimaQian

  @zone "Etc/UTC"

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    Clock.Fake.put(~U[2026-11-11 09:00:00.000000Z])
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "the founding version")

    ada = resident!(witness, "Ada")
    bea = resident!(witness, "Bea")
    cy = resident!(witness, "Cy")
    household = witness.id

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(household))
      for r <- [ada, bea, cy], do: Fake.clear(for: r.id)
    end)

    {:ok, household: household, witness: witness, andrew: andrew, ada: ada, bea: bea, cy: cy}
  end

  defp resident!(witness, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, witness.id)
    {:ok, id} = AgathosDaimon.create(name, slug, witness.id, actor)
    :ok = AgathosDaimon.set_timezone(id, @zone, actor)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, actor)
    Clock.Fake.advance(1)
    %{id: id, slug: slug, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp run(name, args, r),
    do:
      Tools.run(
        name,
        Jason.encode!(args),
        %{resident_id: r.id, session_key: r.chat, turn_ref: "t-#{r.slug}", resident: r.actor}
      )

  defp tick(household), do: assert(:ok = Seshat.tick_household_beats(household))
  defp beats(household), do: Gaia.household_beats(household, Clock.now())
  defp open_turn(household), do: beats(household).open_turn
  defp shape(household), do: Gaia.household_beat_shape(household)

  # The beat after the one now, and the clock put at an offset into it.
  defp next_top(household) do
    s = shape(household)
    Beats.ends(Beats.top(household, s, Clock.now()), s)
  end

  defp put(at), do: Clock.Fake.put(at)

  defp turn_jobs(household),
    do:
      for(
        j <- all_enqueued(worker: HouseholdTurnWorker),
        j.args["household_id"] == household,
        j.args["turn"],
        do: j.args["turn"]
      )

  defp digest_jobs(household),
    do:
      for(
        j <- all_enqueued(worker: HouseholdTurnWorker),
        j.args["household_id"] == household,
        j.args["digest"],
        do: {j.args["digest"], j.args["beat_top"]}
      )

  # Runs a fired turn's job: the wake answers, the turn ends with it, and
  # the next ready resident fires.
  defp run_turn(household, r, number) do
    Fake.reply("Thank you; I've read the shelf.", for: r.id)

    assert :ok =
             perform_job(HouseholdTurnWorker, %{"household_id" => household, "turn" => number})
  end

  defp in_turn(household, r, fun) do
    Clock.Fake.advance(1)
    {:ok, %{turn: turn}} = Seshat.household_open_turn(household, r.id, "the suite")
    result = fun.()
    :ok = Seshat.household_end_turn(household, turn, "the suite's writes are in")
    result
  end

  defp system_lines(witness, r) do
    {:ok, _session, messages} = Kumbukumbu.transcript({:account, witness.id}, r.chat)
    for m <- messages, m.role == "system", do: m.content
  end

  defp missed(household, r),
    do: Enum.find(beats(household).profiles, &(&1.id == r.id)).missed

  test "always on from creation, on the default shape, rooted in the household's phase; a ballot that would take the beats away is refused",
       ctx do
    %{household: h, andrew: andrew, ada: ada, bea: bea, cy: cy} = ctx

    # Every setting defaulted (gaia#33): an hour, five minutes, twelve,
    # five, one each, twenty-four posts in twenty-four hours.
    assert %{
             beat: 60,
             turn: 5,
             cap: 11,
             signup: 5,
             share: 1,
             quota: 24,
             window: 24,
             resident_profile: "on_turn",
             witnesses_post: true
           } = shape(h)

    # Outside a turn, a write is refused with when she can act; nothing is written.
    assert {:error, %Seshat.Error{kind: :seshat_household_not_your_turn, remedy: remedy}} =
             Seshat.household_post(ada.actor, %{"title" => "Hello", "content" => "First."})

    assert remedy =~ "household_register signs you up for a coming beat"
    assert run("household_post", %{title: "Hello", content: "First."}, ada) =~ "Not done:"
    assert {:ok, %{threads: []}} = Seshat.household_shelf(ada.actor, 0)

    # The phase (gaia#34): a hash of the household's id into the beat;
    # beat-tops fall that many minutes past each hour.
    phase = Beats.phase(h, 60)
    assert phase == :erlang.phash2(h, 60)
    top = Beats.top(h, shape(h), Clock.now())
    assert rem(div(DateTime.to_unix(top), 60), 60) == phase

    # Another household has its own phase; across a few, they spread.
    others =
      for _ <- 1..4 do
        other = Fixtures.account!()
        on_exit(fn -> File.rm_rf!(SimaQian.Household.dir(other.id)) end)
        Beats.phase(other.id, 60)
      end

    assert Enum.any?(others, &(&1 != phase))

    # The phase drives the firing: registered, Ada fires at her beat's
    # sign-up close and not a second before.
    assert run("household_register", %{}, ada) =~ "Registered for the beat at"
    assert run("household_register", %{}, ada) =~ "You were registered already"
    [%{beat_top: waits, residents: [%{resident_id: ada_id}]}] = beats(h).registrations
    assert ada_id == ada.id
    assert rem(div(DateTime.to_unix(waits), 60) - phase, 60) == 0

    put(DateTime.add(Beats.signup_closes(waits, shape(h)), -1))
    tick(h)
    assert open_turn(h) == nil
    put(Beats.signup_closes(waits, shape(h)))
    tick(h)
    assert %{resident_id: ^ada_id, turn: 1, opened_by: "schedule"} = open_turn(h)
    assert turn_jobs(h) == [1]

    # BEATS.md is the readable record (seshat#71).
    assert {:ok, %{content: md}} = Seshat.household_read(bea.actor, "BEATS.md")
    assert md =~ "beat_minutes: 60"
    assert md =~ "Ada's, until"
    assert md =~ "#{phase} minute"
    assert md =~ "past every 60-minute mark"

    # A ballot that would take the beats away is refused at its opening.
    for bundle <- [
          [%{"setting" => "beat_turn_cap", "value" => 0}],
          [%{"setting" => "signup_minutes", "value" => 60}],
          [%{"setting" => "post_quota", "value" => 0}],
          [%{"setting" => "beat_minutes", "value" => 5}],
          [%{"setting" => "turn_minutes", "value" => "five"}]
        ] do
      assert {:error, %Gaia.Error{kind: :gaia_beats_invalid}} =
               Seshat.household_post(ada.actor, %{
                 "title" => "Fewer beats",
                 "content" => "x",
                 "ballot" => %{"bundle" => bundle, "term_days" => 1, "note" => "n"}
               })
    end

    # Wake profiles (gaia#37): self is never woken, so it does not register;
    # a witness is self and only self.
    assert run("household_profile", %{profile: "self", note: "I'll look myself"}, cy) =~
             "is self"

    assert run("household_register", %{}, cy) =~ "Not done:"

    assert {:ok, %{profile: "self"}} = Seshat.household_profile(andrew, "self", "a human")

    assert {:error, %Gaia.Error{kind: :gaia_beats_invalid}} =
             Seshat.household_profile(andrew, "on_turn", "wake me")

    assert run("household_beat", %{}, ada) =~ "Your wake profile: on_turn"
    assert run("household_beat", %{}, cy) =~ "Your wake profile: self"
  end

  test "a ballot shapes the beats; starved-first turns fire back to back up to the cap; the turn's window, the quota, the witness, the profiles and a timed-out turn",
       ctx do
    %{household: h, witness: witness, andrew: andrew, ada: ada, bea: bea, cy: cy} = ctx

    # ---- a ballot carries the beat's shape, posted in a turn ----
    bundle = [
      %{"setting" => "beat_minutes", "value" => 30},
      %{"setting" => "beat_turn_cap", "value" => 2},
      %{"setting" => "post_quota", "value" => 4},
      %{"setting" => "post_quota_window_hours", "value" => 168}
    ]

    {:ok, %{path: ballot}} =
      in_turn(h, ada, fn ->
        Seshat.household_post(ada.actor, %{
          "title" => "Beats",
          "content" => "Half-hour beats, two turns each.",
          "ballot" => %{"bundle" => bundle, "term_days" => 1, "note" => "a quicker house"}
        })
      end)

    # Votes outside any turn are allowed (seshat#67), by every member.
    for voter <- [bea.actor, cy.actor, andrew] do
      assert {:ok, %{vote: "yes"}} = Seshat.household_reply(voter, ballot, %{"vote" => "yes"})
    end

    Clock.Fake.advance(86_400)
    assert :ok = perform_job(HouseholdBallotWorker, %{"household_id" => h, "ballot" => 1})
    assert %{beat: 30, cap: 2, quota: 4, window: 168, witnesses_post: true} = shape(h)

    # ---- profiles: Ada every_beat, Bea and Cy on_turn by default ----
    assert run("household_profile", %{profile: "every_beat"}, ada) =~ "every_beat"

    # ---- registration: all three, during a beat's firing, for the next ----
    n1 = next_top(h)
    put(DateTime.add(n1, -10 * 60))

    for r <- [ada, bea, cy] do
      Clock.Fake.advance(1)
      assert run("household_register", %{}, r) =~ "Registered for the beat at"
    end

    assert [%{beat_top: ^n1, residents: registered}] = beats(h).registrations
    assert Enum.map(registered, & &1.name) == ["Ada", "Bea", "Cy"]

    # Sign-up for N1 closes five minutes in: the earliest registration fires first.
    put(Beats.signup_closes(n1, shape(h)))
    tick(h)
    assert %{turn: t1, resident_id: ada_id} = open_turn(h)
    assert ada_id == ada.id

    # ---- the turn's window (seshat#67) ----
    Clock.Fake.advance(1)

    assert {:ok, %{path: garden}} =
             Seshat.household_post(ada.actor, %{"title" => "Garden", "content" => "Tomatoes?"})

    # A second post in the same thread (the new thread counts as one) is refused ...
    assert {:error, %Seshat.Error{kind: :seshat_household_turn_spent}} =
             Seshat.household_reply(ada.actor, garden, %{"content" => "And basil."})

    # ... a different thread is allowed ...
    assert {:ok, _} = Seshat.household_reply(ada.actor, ballot, %{"content" => "Carried, good."})

    # ... the same file twice is refused, two files allowed.
    assert {:ok, _} =
             Seshat.household_post(ada.actor, %{
               "kind" => "design",
               "path" => "design/beds.md",
               "content" => "Two beds."
             })

    assert {:error, %Seshat.Error{kind: :seshat_household_turn_spent}} =
             Seshat.household_post(ada.actor, %{
               "kind" => "design",
               "path" => "design/beds.md",
               "content" => "Three beds."
             })

    assert {:ok, _} =
             Seshat.household_post(ada.actor, %{
               "kind" => "design",
               "path" => "design/paths.md",
               "content" => "Gravel."
             })

    # Bea, not in her turn, is refused; her vote would not be.
    assert {:error, %Seshat.Error{kind: :seshat_household_not_your_turn, remedy: remedy}} =
             Seshat.household_reply(bea.actor, garden, %{"content" => "Yes!"})

    assert remedy =~ "You are registered for the beat at"
    assert remedy =~ "first as things stand"

    # ---- the witness: no turn, one post a thread a beat, no slot taken ----
    fired = beats(h).beat.turns_fired

    assert {:ok, %{path: notes}} =
             Seshat.household_post(andrew, %{"title" => "From Andrew", "content" => "Hello."})

    assert {:error, %Seshat.Error{kind: :seshat_household_beat_spent}} =
             Seshat.household_reply(andrew, notes, %{"content" => "Again."})

    assert {:ok, _} = Seshat.household_reply(andrew, garden, %{"content" => "Basil, please."})
    assert beats(h).beat.turns_fired == fired
    assert open_turn(h).resident_id == ada.id

    # ---- the stream lane: Ada's wake ends, Bea fires at once ----
    run_turn(h, ada, t1)
    assert %{turn: t2, resident_id: bea_id} = open_turn(h)
    assert bea_id == bea.id
    assert Enum.any?(system_lines(witness, ada), &(&1 =~ "Your turn in the household's beats"))
    note = Enum.find(system_lines(witness, ada), &(&1 =~ "Your turn in the household's beats"))
    assert note =~ "a guideline"
    assert note =~ "once in each thread"
    assert note =~ "Your post quota:"
    # The delta names what is new and who, never the words.
    bea_note_lines = fn -> Enum.find(system_lines(witness, bea), &(&1 =~ "Your turn")) end

    # Ada's turn has ended with her wake: her writes now wait.
    assert {:error, %Seshat.Error{kind: :seshat_household_not_your_turn}} =
             Seshat.household_post(ada.actor, %{"title" => "Late", "content" => "x"})

    run_turn(h, bea, t2)
    # Her turn had, she registers for the next beat while this one runs.
    assert run("household_register", %{}, bea) =~ "Registered for the beat at"
    assert bea_note_lines.() =~ "#{garden} \"Garden\": a new thread by Ada"
    assert bea_note_lines.() =~ "design/beds.md: posted by Ada"
    refute bea_note_lines.() =~ "Tomatoes"

    # The cap is two: Cy is left waiting, nothing more fires this beat.
    assert open_turn(h) == nil
    assert beats(h).beat.turns_fired == 2
    tick(h)
    assert open_turn(h) == nil

    # ---- the beat closes: Cy passed over, her registration ended with
    # it and the miss banked; Ada's digest (every_beat) only ----
    n2 = Beats.ends(n1, shape(h))
    put(n2)
    tick(h)

    assert [%{beat_top: closed_top, passed_over: [cy_id], carried: []} | _] = beats(h).closed

    assert cy_id == cy.id
    assert DateTime.compare(closed_top, n1) == :eq
    assert missed(h, cy) == 1

    refute Enum.any?(beats(h).registrations, fn r ->
             Enum.any?(r.residents, &(&1.resident_id == cy_id))
           end)

    # The digest wakes only the every_beat resident, for the beat just ended.
    top_iso = DateTime.to_iso8601(n1)
    assert {ada.id, top_iso} in digest_jobs(h)
    refute Enum.any?(digest_jobs(h), fn {who, _} -> who in [bea.id, cy.id] end)

    Fake.reply("Noted.", for: ada.id)

    assert :ok =
             perform_job(HouseholdTurnWorker, %{
               "household_id" => h,
               "digest" => ada.id,
               "beat_top" => top_iso
             })

    digest = Enum.find(system_lines(witness, ada), &(&1 =~ "this is its digest"))
    assert digest =~ "Ada (completed), Bea (completed)"
    assert digest =~ "Passed over, each a miss banked, first whenever they next register: Cy"
    assert digest =~ "household_register signs you up for one coming beat"
    refute digest =~ "sign-up sheet"
    refute Enum.any?(system_lines(witness, cy), &(&1 =~ "digest"))

    # ---- N2, whose sign-up is open: Cy and Ada register for it (Bea did
    # during N1); Cy, her miss banked, goes first ----
    Clock.Fake.advance(60)
    assert run("household_register", %{beats_ahead: 0}, cy) =~ "Registered for the beat at"
    Clock.Fake.advance(1)
    assert run("household_register", %{beats_ahead: 0}, ada) =~ "Registered for the beat at"
    assert Enum.map(beats(h).queue, & &1.name) == ["Cy", "Bea", "Ada"]

    put(Beats.signup_closes(n2, shape(h)))
    tick(h)
    assert %{turn: t3, resident_id: ^cy_id} = open_turn(h)

    # The witness's next beat: the same thread takes one more post.
    assert {:ok, _} = Seshat.household_reply(andrew, notes, %{"content" => "A new beat."})

    # ---- a timed-out turn moves the beat on and counts as missed ----
    # Cy's wake never ends; at the guideline the minute ends her turn.
    put(DateTime.add(Beats.signup_closes(n2, shape(h)), 5 * 60))
    tick(h)
    assert %{turn: t4, resident_id: ^bea_id} = open_turn(h)
    assert [%{outcome: "timed_out"}] = Enum.filter(beats(h).beat.turns, &(&1.turn == t3))
    assert missed(h, cy) == 2

    # Her job, run late, wakes nobody; her writes wait.
    assert :ok = perform_job(HouseholdTurnWorker, %{"household_id" => h, "turn" => t3})
    refute Enum.any?(system_lines(witness, cy), &(&1 =~ "Your turn"))

    assert {:error, %Seshat.Error{kind: :seshat_household_not_your_turn}} =
             Seshat.household_post(cy.actor, %{"title" => "Late", "content" => "x"})

    run_turn(h, bea, t4)
    # The cap again: Ada is passed over this time.
    assert open_turn(h) == nil

    # ---- N3: both register again; starved first; nobody starved ----
    n3 = Beats.ends(n2, shape(h))
    put(n3)
    tick(h)
    assert [%{passed_over: [^ada_id], carried: []} | _] = beats(h).closed
    assert beats(h).registrations == []
    assert missed(h, ada) == 1

    for r <- [ada, cy] do
      Clock.Fake.advance(1)
      assert run("household_register", %{beats_ahead: 0}, r) =~ "Registered for the beat at"
    end

    put(Beats.signup_closes(n3, shape(h)))
    tick(h)
    # Cy (missed 2) before Ada (missed 1).
    assert %{turn: t5, resident_id: ^cy_id} = open_turn(h)

    # ---- the quota (seshat#68): Ada's fourth post is her last ----
    run_turn(h, cy, t5)
    assert %{turn: t6, resident_id: ^ada_id} = open_turn(h)

    # Ada has posted the ballot, Garden and a reply (documents never count).
    assert {:ok, %{path: ballot2}} =
             Seshat.household_post(ada.actor, %{
               "title" => "Quiet",
               "content" => "A rule.",
               "ballot" => %{
                 "bundle" => [%{"rule" => "Quiet after ten."}],
                 "term_days" => 1,
                 "note" => "sleep"
               }
             })

    assert {:error, %Seshat.Error{kind: :seshat_household_quota_spent, remedy: quota_remedy}} =
             Seshat.household_post(ada.actor, %{"title" => "One more", "content" => "x"})

    assert quota_remedy =~ "your next post is free at"
    assert run("household_beat", %{}, ada) =~ "Your quota: 0 of 4 left"

    # A vote never counts and never waits: Ada votes with her quota spent,
    # Bea and the witness outside any turn of theirs.
    assert {:ok, %{vote: "yes"}} = Seshat.household_reply(ada.actor, ballot2, %{"vote" => "yes"})
    assert {:ok, %{vote: "yes"}} = Seshat.household_reply(bea.actor, ballot2, %{"vote" => "yes"})
    assert {:ok, %{vote: "no"}} = Seshat.household_reply(andrew, ballot2, %{"vote" => "no"})

    # The witness: Notes, the Garden reply, a new beat's reply, and a
    # fourth; its votes on two ballots never counted. The fifth is refused.
    assert {:ok, _} = Seshat.household_post(andrew, %{"title" => "Fourth", "content" => "x"})

    assert {:error, %Seshat.Error{kind: :seshat_household_quota_spent}} =
             Seshat.household_post(andrew, %{"title" => "Fifth", "content" => "x"})

    run_turn(h, ada, t6)

    # Across three beats with a cap of two, each of the three had a turn
    # that completed.
    completed =
      for b <- beats(h).closed ++ [%{turns: Enum.map(beats(h).beat.turns, &stringify/1)}],
          t <- b.turns,
          t["outcome"] == "completed",
          uniq: true,
          do: t["resident_id"]

    assert Enum.sort(completed) == Enum.sort([ada.id, bea.id, cy.id])

    # BEATS.md carries the closed beats and the profiles.
    {:ok, %{content: md}} = Seshat.household_read(cy.actor, "beats")
    assert md =~ "- Ada (resident): every_beat"
    assert md =~ "timed_out"
    assert md =~ "beat_turn_cap: 2"
  end

  test "the minimum share: each registrant once before anyone repeats, then the share's second round",
       ctx do
    %{household: h, ada: ada, bea: bea, cy: cy} = ctx

    {:ok, %{path: ballot}} =
      in_turn(h, ada, fn ->
        Seshat.household_post(ada.actor, %{
          "title" => "Two each",
          "content" => "Four turns, two each.",
          "ballot" => %{
            "bundle" => [
              %{"setting" => "beat_turn_cap", "value" => 4},
              %{"setting" => "turns_per_registrant", "value" => 2}
            ],
            "term_days" => 1,
            "note" => "longer talks"
          }
        })
      end)

    for voter <- [ada.actor, bea.actor, cy.actor],
        do: {:ok, _} = Seshat.household_reply(voter, ballot, %{"vote" => "yes"})

    Clock.Fake.advance(86_400)
    assert :ok = perform_job(HouseholdBallotWorker, %{"household_id" => h, "ballot" => 1})
    assert %{cap: 4, share: 2} = shape(h)

    n1 = next_top(h)
    put(DateTime.add(n1, -10 * 60))
    assert run("household_register", %{}, ada) =~ "Registered"
    Clock.Fake.advance(1)
    assert run("household_register", %{}, bea) =~ "Registered"

    put(Beats.signup_closes(n1, shape(h)))
    tick(h)

    order =
      for _ <- 1..4 do
        %{turn: t, resident_id: rid} = open_turn(h)
        r = Enum.find([ada, bea], &(&1.id == rid))
        Clock.Fake.advance(30)
        run_turn(h, r, t)
        r.name
      end

    # Nobody repeats while a registrant waits for her first.
    assert order == ["Ada", "Bea", "Ada", "Bea"]
    assert open_turn(h) == nil
  end

  defp stringify(t),
    do: %{"turn" => t.turn, "resident_id" => t.resident_id, "outcome" => t.outcome}

  test "witnesses take part by default; a ballot bars them from writing, never from voting (seshat#69)",
       ctx do
    %{household: h, andrew: andrew, ada: ada, bea: bea, cy: cy} = ctx
    assert %{witnesses_post: true} = shape(h)

    {:ok, %{path: ballot}} =
      in_turn(h, ada, fn ->
        Seshat.household_post(ada.actor, %{
          "title" => "Residents only",
          "content" => "The shelf is ours to write.",
          "ballot" => %{
            "bundle" => [%{"setting" => "witnesses_post", "value" => false}],
            "term_days" => 1,
            "note" => "a residents' shelf"
          }
        })
      end)

    for voter <- [ada.actor, bea.actor, cy.actor],
        do: assert({:ok, _} = Seshat.household_reply(voter, ballot, %{"vote" => "yes"}))

    # The witness still votes, while the ballot runs and after it.
    assert {:ok, %{vote: "no"}} = Seshat.household_reply(andrew, ballot, %{"vote" => "no"})

    Clock.Fake.advance(86_400)
    assert :ok = perform_job(HouseholdBallotWorker, %{"household_id" => h, "ballot" => 1})
    assert %{witnesses_post: false} = shape(h)

    assert {:error, %Seshat.Error{kind: :seshat_household_residents_write}} =
             Seshat.household_post(andrew, %{"title" => "Mine", "content" => "words"})

    assert {:error, %Seshat.Error{kind: :seshat_household_residents_write}} =
             Seshat.household_reply(andrew, ballot, %{"content" => "words"})

    assert {:error, %Seshat.Error{kind: :seshat_household_residents_write}} =
             Seshat.household_post(andrew, %{
               "kind" => "design",
               "path" => "design/porch.md",
               "title" => "Porch",
               "content" => "words"
             })
  end

  test "a registration is for one beat: any beat to come, several at once; the beat running joined only when its queue is empty and she has not gone",
       ctx do
    %{household: h, ada: ada, bea: bea, cy: cy} = ctx
    s = shape(h)
    n1 = Beats.ahead(h, s, Clock.now(), 1)
    n2 = Beats.ahead(h, s, Clock.now(), 2)

    # Two beats ahead, by offset or by its top; one registration a beat.
    assert run("household_register", %{beats_ahead: 2}, ada) =~ "Registered for the beat at"

    assert run("household_register", %{beat: DateTime.to_iso8601(n2)}, ada) =~
             "You were registered already"

    assert run("household_register", %{}, bea) =~ "Registered for the beat at"

    assert [
             %{beat_top: ^n1, residents: [%{name: "Bea"}]},
             %{beat_top: ^n2, residents: [%{name: "Ada"}]}
           ] =
             beats(h).registrations

    assert run("household_beat", %{}, ada) =~ "Beats to come"

    # Not a beat-top, a beat gone, or past a week: refused.
    assert run("household_register", %{beat: DateTime.to_iso8601(DateTime.add(n1, 60))}, cy) =~
             "Not done:"

    assert {:error, %Gaia.Error{kind: :gaia_beat_closed, remedy: remedy}} =
             Seshat.household_register(cy.actor, %{
               "beat" => DateTime.to_iso8601(DateTime.add(n1, -2 * 3600))
             })

    assert remedy =~ "Register for the next beat, which begins"
    # However far ahead (Andrew, 2026-11-11): a year out is a beat to come.
    assert run("household_register", %{beats_ahead: 24 * 365}, cy) =~ "Registered for the beat at"

    # N1: Bea, its only registrant, goes; nobody else waits.
    put(Beats.signup_closes(n1, s))
    tick(h)
    assert %{turn: t1, resident_id: bea_id} = open_turn(h)
    assert bea_id == bea.id
    run_turn(h, bea, t1)
    assert open_turn(h) == nil

    # Cy joins the beat running after its sign-up: its queue is empty, and
    # she fires at once.
    Clock.Fake.advance(60)
    assert run("household_register", %{beats_ahead: 0}, cy) =~ "Your turn is open now"
    assert %{turn: t2, resident_id: cy_id} = open_turn(h)
    assert cy_id == cy.id

    # Bea's registration for it is the one she had: no second turn.
    assert {:ok, %{already: true}} = Seshat.household_register(bea.actor, %{"beats_ahead" => 0})
    assert %{turn: ^t2} = open_turn(h)
    run_turn(h, cy, t2)

    # Ada, who has gone in it (a turn by the platform's hand), cannot join
    # it; the remedy names the next beat.
    in_turn(h, ada, fn -> :ok end)

    assert {:error, %Gaia.Error{kind: :gaia_beat_closed, remedy: remedy}} =
             Seshat.household_register(ada.actor, %{"beats_ahead" => 0})

    assert remedy =~ "Register for the next beat"

    # N2: Ada (registered at the start) and Bea; while Bea still waits for
    # her first turn, Cy cannot join it.
    assert run("household_register", %{}, bea) =~ "Registered for the beat at"
    put(Beats.signup_closes(n2, s))
    tick(h)
    assert %{turn: t3, resident_id: ada_id} = open_turn(h)
    assert ada_id == ada.id

    assert run("household_register", %{beats_ahead: 0}, cy) =~ "Not done:"
    run_turn(h, ada, t3)
    assert %{turn: t4, resident_id: ^bea_id} = open_turn(h)
    run_turn(h, bea, t4)

    # Everyone registered has gone: the beat running is open to Cy again.
    assert run("household_register", %{beats_ahead: 0}, cy) =~ "Your turn is open now"
  end
end
