defmodule Oneiroi.HouseholdCommunicationTest do
  @moduledoc """
  Household communication (design household-communication §9, the
  witness's approval of 2026-11-11), verified as its §0 asks: a scratch
  household of one witness and two residents, end to end. Membership and
  the contract's signature at join (gaia#27, #28), the household's
  repository read by every member and written by its residents under
  their own names (sima-qian#51, #52; seshat#58 to #61), a thread posted
  and replied to by both residents (seshat#59), the watch poking the
  other resident and going silent after its term (gaia#32, seshat#62,
  sunna#49), ballots with their proposer's terms and their bundles fixed
  (gaia#29 to #31, seshat#63), mail between the residents and the
  witness, and the repository travelling with a backup (sima-qian#53).
  The in-memory provider throughout; no network.
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
  alias Oneiroi.Seshat.HouseholdBallotWorker
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.Sunna

  @zone "America/New_York"
  @job Actor.new(:job, "household_ballots")

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)

    # The founding witness proposes version 1 before anyone else joins:
    # prose alone, empty of rules (design §6).
    assert {:ok, %{in_force: %{version: 1, rules: [], settings: %{}}}} =
             Seshat.household_propose_contract(
               andrew,
               "We share this house. What we make together lives here; what is each of ours stays in our own repositories.",
               "the founding version"
             )

    lily = resident!(witness, "Lily")
    Clock.Fake.advance(1)
    iris = resident!(witness, "Iris")
    household = witness.id

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(household))

      for r <- [lily, iris] do
        File.rm_rf!(SimaQian.Backup.dir(r.id))
      end
    end)

    {:ok, household: household, witness: witness, andrew: andrew, lily: lily, iris: iris}
  end

  defp resident!(witness, name) do
    slug = "#{String.downcase(name)}-#{System.unique_integer([:positive])}"
    actor = Actor.new(:witness, witness.id)
    {:ok, id} = AgathosDaimon.create(name, slug, witness.id, actor)
    :ok = AgathosDaimon.set_timezone(id, @zone, actor)
    {:ok, chat} = Kumbukumbu.main_session(id, witness.id, actor)
    %{id: id, slug: slug, name: name, actor: Actor.new(:resident, id), chat: chat}
  end

  defp turn(r),
    do: %{resident_id: r.id, session_key: r.chat, turn_ref: "t-#{r.slug}", resident: r.actor}

  defp run(name, args, r), do: Tools.run(name, Jason.encode!(args), turn(r))

  defp authors(household, path) do
    {:ok, commits} = SimaQian.household_log(household, path, 50)
    Enum.map(commits, & &1.author)
  end

  defp watch_letters(r),
    do: Enum.filter(Kumbukumbu.letters(r.id), &(&1.from_name == "the household"))

  test "a household of one witness and two residents: membership, the shared repository, a thread, the watch and mail",
       ctx do
    %{household: household, andrew: andrew, lily: lily, iris: iris} = ctx

    # ---- membership, and the contract signed at join ----
    assert %{id: ^household, members: members} = Gaia.resident_household(lily.id)
    assert Gaia.resident_household(iris.id).id == household

    assert [
             %{kind: "resident", name: "Lily", signed_version: 1},
             %{kind: "resident", name: "Iris", signed_version: 1},
             %{kind: "witness", name: "Lily and Iris's witness", signed_version: 1}
           ] = members

    assert Enum.all?([andrew, lily.actor, iris.actor], &Gaia.household_member?(household, &1))
    stranger = Fixtures.account!()
    refute Gaia.household_member?(household, Actor.new(:witness, stranger.id))

    # Another account is in a household of its own, and reads only that.
    assert {:ok, %{household_id: other}} =
             Seshat.household_shelf(Actor.new(:witness, stranger.id), 0)

    assert other != household
    on_exit(fn -> File.rm_rf!(SimaQian.Household.dir(other)) end)

    # ---- the repository, provisioned on first use ----
    assert run("household_read", %{}, lily) =~ "Nothing posted yet."
    dir = SimaQian.Household.dir(household)
    assert File.regular?(Path.join(dir, "threads/kind.json"))

    assert %{"kind" => "thread", "container" => true} =
             Jason.decode!(File.read!(Path.join(dir, "threads/kind.json")))

    assert File.read!(Path.join(dir, "CONTRACT.md")) =~ "version 1"
    assert File.read!(Path.join(dir, "CONTRACT.md")) =~ "Iris (resident), joined"

    # ---- a thread posted and replied to by both residents ----
    assert "Posted threads/" <> _ =
             posted =
             run(
               "household_post",
               %{title: "The garden", content: "Shall we plant tomatoes?"},
               lily
             )

    thread = posted |> String.trim_leading("Posted ") |> String.trim_trailing(".")

    assert run("household_reply", %{thread: thread, content: "Yes, and basil."}, iris) =~
             "as reply #1"

    assert run(
             "household_reply",
             %{thread: thread, content: "Basil it is.", in_reply_to: 1},
             lily
           ) =~
             "as reply #2"

    # Each write is a commit under its writer's name; the trunk is never rewritten.
    assert authors(household, thread) == ["Lily", "Iris", "Lily"]
    assert authors(household, thread <> "/trunk.md") == ["Lily"]

    # A document of a household kind, posted once.
    assert run(
             "household_post",
             %{kind: "design", path: "design/beds.md", content: "Two beds."},
             iris
           ) ==
             "Posted design/beds.md."

    assert {:error, %Seshat.Error{kind: :seshat_household_written}} =
             Seshat.household_post(iris.actor, %{
               kind: "design",
               path: "design/beds.md",
               content: "again"
             })

    # ---- every member reads it whole: both residents and the witness ----
    for reader <- [andrew, lily.actor, iris.actor] do
      assert {:ok, %{kind: "thread", content: text, replies: [_, _]}} =
               Seshat.household_read(reader, thread)

      assert text =~ "Shall we plant tomatoes?"
      assert text =~ "Reply #1 by Iris"
      assert text =~ "Reply #2 by Lily"

      assert {:ok,
              %{threads: [%{path: ^thread, replies: 2}], documents: [%{path: "design/beds.md"}]}} =
               Seshat.household_shelf(reader, 0)
    end

    # A stranger, in a household of its own, cannot reach this one's thread.
    assert {:error, %Seshat.Error{kind: :seshat_household_no_such_thread}} =
             Seshat.household_read(Actor.new(:witness, stranger.id), thread)

    # The witness reads; it does not write the rooms.
    assert {:error, %Seshat.Error{kind: :seshat_household_residents_write}} =
             Seshat.household_post(andrew, %{title: "Mine", content: "words"})

    assert {:error, %Seshat.Error{kind: :seshat_household_residents_write}} =
             Seshat.household_reply(andrew, thread, %{"content" => "words"})

    # A resident's own library refuses the household's kind.
    assert {:error, %Seshat.Error{}} =
             Seshat.write(lily.id, "threads/x/trunk.md", "not here", lily.actor)

    # ---- the watch: opt-in, for a term she states ----
    assert watch_letters(iris) == []

    assert run("household_watch", %{thread: thread, hours: 24}, iris) =~
             "Watching #{thread} until"

    assert run("household_reply", %{thread: thread, content: "I'll water them."}, lily) =~
             "as reply #3"

    assert [%{to_name: "Oneiroi chat", text: poke}] = watch_letters(iris)
    assert poke =~ "Lily replied in the household thread #{thread}"
    refute poke =~ "water"
    # The author is never poked, and nobody who did not ask.
    assert watch_letters(lily) == []

    # Her own reply does not poke her.
    assert run("household_reply", %{thread: thread, content: "Thank you."}, iris) =~ "as reply #4"
    assert [_one] = watch_letters(iris)

    # The poke wakes her chat, naming the letter and never its words.
    Fake.clear()
    Fake.reply("I'll look.", for: iris.id)
    assert :ok = Sunna.tick(iris.id)

    {:ok, _session, messages} = Kumbukumbu.transcript({:account, ctx.witness.id}, iris.chat)
    assert Enum.any?(messages, &(&1.role == "system" and &1.content =~ "from the household"))
    refute Enum.any?(messages, &(&1.role == "system" and &1.content =~ "water"))

    # Past the term, silence: nothing sent, nothing to unsubscribe.
    Clock.Fake.advance(25 * 3600)

    assert run("household_reply", %{thread: thread, content: "Tomatoes are up."}, lily) =~
             "as reply #5"

    assert [_still_one] = watch_letters(iris)

    # Never on by default, and the term is hers to state, within a week.
    assert {:error, %Gaia.Error{kind: :gaia_watch_invalid}} =
             Seshat.household_watch(iris.actor, thread, 0)

    assert {:error, %Gaia.Error{kind: :gaia_not_a_member}} =
             Seshat.household_watch(andrew, thread, 24)

    # ---- mail: the house letters, between each resident and the witness ----
    {:ok, %{number: to_lily}} =
      Kumbukumbu.send_letter(
        lily.id,
        nil,
        %{to: "Oneiroi chat", text: "Dinner at seven."},
        andrew
      )

    {:ok, %{number: to_iris}} =
      Kumbukumbu.send_letter(
        iris.id,
        nil,
        %{to: "Oneiroi chat", text: "Dinner at seven."},
        andrew
      )

    assert [%{number: ^to_lily, from_name: "witness"}] = Kumbukumbu.inbox(lily.id, lily.chat)
    assert Enum.any?(Kumbukumbu.inbox(iris.id, iris.chat), &(&1.number == to_iris))

    assert run("letter_send", %{to: "house", text: "Coming.", in_reply_to: to_lily}, lily) =~
             "Sent letter"

    assert run("letter_send", %{to: "house", text: "Me too.", in_reply_to: to_iris}, iris) =~
             "Sent letter"

    # The witness reads every letter of each resident's.
    assert Enum.any?(
             Kumbukumbu.letters(lily.id),
             &(&1.text == "Coming." and &1.in_reply_to == to_lily)
           )

    assert Enum.any?(
             Kumbukumbu.letters(iris.id),
             &(&1.text == "Me too." and &1.in_reply_to == to_iris)
           )

    # Between the two residents there is no house letter: a letter is the
    # work log between one resident's own conversations (kumbukumbu#44),
    # and her name is no conversation of Lily's. The household thread is
    # where they talk; this pins the gap the build did not close.
    assert run("letter_send", %{to: "Iris", text: "Hello"}, lily) =~ "Not done:"
  end

  test "a ballot's bundle is fixed once it opens: every change is refused, and the amendment is exactly the bundle voted on",
       ctx do
    %{household: household, andrew: andrew, lily: lily, iris: iris} = ctx

    bundle = [
      %{"rule" => "Quiet after ten in the shared rooms."},
      %{"setting" => "quiet_hours", "value" => "22:00-07:00"}
    ]

    assert {:ok, %{path: thread, ballot: %{ballot: 1, closes_at: closes_at}}} =
             Seshat.household_post(lily.actor, %{
               "title" => "Quiet hours",
               "content" => "A rule and a setting, together.",
               "ballot" => %{"bundle" => bundle, "term_days" => 3, "note" => "the evenings"}
             })

    assert closes_at == DateTime.add(Clock.now(), 3 * 86_400, :second)

    # The close is a job scheduled for the instant the term ends.
    assert_enqueued(
      worker: HouseholdBallotWorker,
      args: %{"household_id" => household, "ballot" => 1},
      scheduled_at: closes_at
    )

    # The trunk states the bundle as it was fixed.
    {:ok, %{content: trunk_text}} = Seshat.household_read(iris.actor, thread)
    assert trunk_text =~ "1. Rule: Quiet after ten in the shared rooms."
    assert trunk_text =~ "2. Setting: quiet_hours = 22:00-07:00"

    # Changing, adding to or removing from the bundle while it runs is
    # refused, by every way there is to try:
    # opening the thread's ballot again with another bundle (an addition,
    # a removal, a change) ...
    for changed <- [
          bundle ++ [%{"rule" => "No drums."}],
          [hd(bundle)],
          [%{"rule" => "Quiet after nine."}, List.last(bundle)]
        ] do
      assert {:error, %Gaia.Error{kind: :gaia_ballot_fixed}} =
               Gaia.open_household_ballot(household, thread, changed, 3, "amend it", iris.actor)
    end

    # ... writing over its trunk ...
    assert {:error, %Seshat.Error{kind: :seshat_household_invalid}} =
             Seshat.household_post(iris.actor, %{
               "kind" => "design",
               "path" => thread <> "/trunk.md",
               "content" => "1. Rule: No drums."
             })

    # ... and a reply proposing more, which is words beside the bundle.
    assert {:ok, %{vote: "yes"}} =
             Seshat.household_reply(iris.actor, thread, %{
               "vote" => "yes",
               "content" => "Yes; and let's add no drums after nine."
             })

    # Every member votes once, the witness as a resident does.
    assert {:ok, %{vote: "yes"}} = Seshat.household_reply(lily.actor, thread, %{"vote" => "yes"})
    assert {:ok, %{vote: "no"}} = Seshat.household_reply(andrew, thread, %{"vote" => "no"})

    assert {:error, %Gaia.Error{kind: :gaia_ballot_voted}} =
             Seshat.household_reply(lily.actor, thread, %{"vote" => "no"})

    # Before the term ends it cannot close.
    assert {:error, %Gaia.Error{kind: :gaia_ballot_open}} =
             Seshat.close_household_ballot(household, 1, @job)

    Clock.Fake.advance(3 * 86_400)

    assert {:error, %Gaia.Error{kind: :gaia_ballot_closed}} =
             Seshat.household_reply(iris.actor, thread, %{"vote" => "no"})

    # The scheduled job closes it: two of three members, carried whole.
    assert :ok = perform_job(HouseholdBallotWorker, %{"household_id" => household, "ballot" => 1})

    contract = Gaia.household_contract(household)

    assert %{version: 2, ballot: 1, rules: ["Quiet after ten in the shared rooms."]} =
             contract.in_force

    assert contract.in_force.settings == %{"quiet_hours" => "22:00-07:00"}
    # Exactly the bundle voted on: nothing the reply proposed came in.
    assert contract.in_force.bundle == bundle
    assert [%{bundle: ^bundle, passed: true, yes: 2, no: 1, members: 3}] = contract.ballots
    refute Enum.any?(contract.in_force.rules, &(&1 =~ "drums"))

    md = File.read!(Path.join(SimaQian.Household.dir(household), "CONTRACT.md"))
    assert md =~ "version 2"
    assert md =~ "1. Quiet after ten in the shared rooms."
    assert md =~ "quiet_hours: 22:00-07:00"

    {:ok, %{content: closed_text}} = Seshat.household_read(andrew, thread)
    assert closed_text =~ "Ballot #1 closed. Carried: 2 yes and 1 no of 3 members"
  end

  test "a ballot's term is its proposer's: two ballots opened together close each on its own term",
       ctx do
    %{household: household, andrew: andrew, lily: lily, iris: iris} = ctx

    {:ok, %{path: short, ballot: %{ballot: 1, closes_at: short_end}}} =
      Seshat.household_post(lily.actor, %{
        "title" => "Shoes off",
        "content" => "One rule.",
        "ballot" => %{
          "bundle" => [%{"rule" => "Shoes off inside."}],
          "term_days" => 1,
          "note" => "floors"
        }
      })

    {:ok, %{path: long, ballot: %{ballot: 2, closes_at: long_end}}} =
      Seshat.household_post(iris.actor, %{
        "title" => "A cat",
        "content" => "One setting.",
        "ballot" => %{
          "bundle" => [%{"setting" => "cat", "value" => true}],
          "term_days" => 5,
          "note" => "company"
        }
      })

    now = Clock.now()
    assert short_end == DateTime.add(now, 86_400, :second)
    assert long_end == DateTime.add(now, 5 * 86_400, :second)

    for voter <- [lily.actor, iris.actor, andrew],
        do: assert({:ok, _} = Seshat.household_reply(voter, short, %{"vote" => "yes"}))

    assert {:ok, _} = Seshat.household_reply(iris.actor, long, %{"vote" => "yes"})

    # A day on: the first closes on its term; the second's still runs.
    Clock.Fake.advance(86_400)
    assert {:ok, %{passed: true, version: 2}} = Seshat.close_household_ballot(household, 1, @job)

    assert {:error, %Gaia.Error{kind: :gaia_ballot_open}} =
             Seshat.close_household_ballot(household, 2, @job)

    assert {:ok, _} = Seshat.household_reply(lily.actor, long, %{"vote" => "no"})

    # Closing twice is no second outcome.
    assert {:ok, :closed} = Seshat.close_household_ballot(household, 1, @job)

    # Five days from the opening: the second closes on its own term, one
    # yes of three, and fails whole: no new version.
    Clock.Fake.advance(4 * 86_400 - 1)

    assert {:error, %Gaia.Error{kind: :gaia_ballot_open}} =
             Seshat.close_household_ballot(household, 2, @job)

    Clock.Fake.advance(1)

    assert {:ok, %{passed: false, yes: 1, no: 1, members: 3, version: nil}} =
             Seshat.close_household_ballot(household, 2, @job)

    contract = Gaia.household_contract(household)
    assert %{version: 2, rules: ["Shoes off inside."], settings: %{}} = contract.in_force
    assert [%{number: 2, passed: false}, %{number: 1, passed: true}] = contract.ballots

    # No platform term: the proposer must set one.
    assert {:error, %Gaia.Error{kind: :gaia_ballot_invalid}} =
             Seshat.household_post(lily.actor, %{
               "title" => "No term",
               "content" => "x",
               "ballot" => %{"bundle" => [%{"rule" => "r"}], "note" => "n"}
             })
  end

  test "the household's repository travels with a resident's backup, titled by its membership",
       ctx do
    %{lily: lily, iris: iris} = ctx

    {:ok, %{path: thread}} =
      Seshat.household_post(iris.actor, %{"title" => "Hello", "content" => "From Iris."})

    bare = Path.join(System.tmp_dir!(), "oneiroi-bare-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    on_exit(fn -> File.rm_rf!(bare) end)
    :ok = SimaQian.set_remote(lily.id, bare, nil, ctx.andrew)
    Clock.Fake.advance(120)

    assert {:ok, %{commits: commits}} = SimaQian.backup(lily.id, ctx.andrew)
    assert Enum.any?(commits, &match?({"household", _}, &1))

    working = SimaQian.Backup.dir(lily.id)
    assert File.read!(Path.join([working, "household", thread, "trunk.md"])) =~ "From Iris."
    members = File.read!(Path.join(working, "household/MEMBERS.md"))
    assert members =~ "# The household of Lily, Iris"
    assert members =~ "- Iris, a resident"
    refute members =~ "@"
  end
end
