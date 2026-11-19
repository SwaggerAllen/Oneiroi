defmodule Oneiroi.Seshat.WitnessBeatsTest do
  @moduledoc """
  The witnesses' beat rules (gaia#47; design/workspaces.md §7): a witness
  has a turn's allowance each beat by default, once in each thread and to
  each document, a vote never counted; a
  ballot may set `witness_posts` to `queue_emptied` (again once nobody
  waits in the queue) or `unbounded` (the small household's: no bound,
  no quota). The in-memory provider; no network.
  """
  use Oneiroi.DataCase, async: false
  use Oban.Testing, repo: Oneiroi.Repo

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Gaia.Beats
  alias Oneiroi.Seshat
  alias Oneiroi.Seshat.HouseholdBallotWorker
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "wren-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Wren", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    {:ok, andrew: andrew, wren: Actor.new(:resident, id), household: Gaia.household_of(andrew)}
  end

  defp post(ctx, title),
    do: Seshat.household_post(ctx.andrew, %{"title" => title, "content" => "Words."})

  test "the setting: three rules, per_beat by default", _ctx do
    assert Beats.defaults()["witness_posts"] == "per_beat"
    assert Beats.shape(%{}).witness_rule == "per_beat"
    assert Beats.setting_ok?("witness_posts", "unbounded")
    assert Beats.setting_ok?("witness_posts", "queue_emptied")
    refute Beats.setting_ok?("witness_posts", "always")
  end

  # gaia#49: the catalog the Charter proposes from is every setting the
  # beats read, each taking what setting_ok? takes.
  test "the settings catalog names every beat setting, with what it takes" do
    catalog = Beats.catalog()
    assert Enum.sort(Enum.map(catalog, & &1.key)) == Enum.sort(Beats.keys())

    for k <- catalog do
      assert is_binary(k.label) and is_binary(k.about)

      case k.type do
        "integer" -> assert Beats.setting_ok?(k.key, k.min) and Beats.setting_ok?(k.key, k.max)
        "choice" -> assert Enum.all?(k.options, &Beats.setting_ok?(k.key, &1))
        "boolean" -> assert Beats.setting_ok?(k.key, true)
      end
    end

    assert %{type: "choice", options: ["per_beat", "queue_emptied", "unbounded"]} =
             Enum.find(catalog, &(&1.key == "witness_posts"))
  end

  test "by default a turn's allowance each beat: once in each thread; the next beat, again",
       ctx do
    assert {:ok, %{path: first}} = post(ctx, "First")

    assert {:error, %{kind: :seshat_household_beat_spent, remedy: remedy}} =
             Seshat.household_reply(ctx.andrew, first, %{"content" => "More."})

    assert remedy =~ "witness_posts"
    assert {:ok, _} = post(ctx, "Second")

    Clock.Fake.advance(3_600)
    assert {:ok, _} = Seshat.household_reply(ctx.andrew, first, %{"content" => "More."})
  end

  test "a ballot unbounds the witness: posts back to back", ctx do
    {:ok, %{path: ballot}} =
      Seshat.household_post(ctx.andrew, %{
        "title" => "A small house",
        "content" => "Let the witness talk.",
        "ballot" => %{
          "bundle" => [%{"setting" => "witness_posts", "value" => "unbounded"}],
          "term_days" => 1,
          "note" => "we are three"
        }
      })

    for voter <- [ctx.andrew, ctx.wren],
        do: {:ok, _} = Seshat.household_reply(voter, ballot, %{"vote" => "yes"})

    Clock.Fake.advance(86_400)

    assert :ok =
             perform_job(HouseholdBallotWorker, %{"household_id" => ctx.household, "ballot" => 1})

    assert Gaia.household_beat_shape(ctx.household).witness_rule == "unbounded"

    {:ok, %{path: thread}} = post(ctx, "Back to back")

    for n <- 1..3,
        do: assert({:ok, _} = Seshat.household_reply(ctx.andrew, thread, %{"content" => "#{n}"}))
  end

  # gaia#54, seshat#91 (the witness, 2026-11-18: "some settings changes
  # are just too urgent or too small to merit waiting a full day").
  test "a ballot every member carries closes at once; short of every member it waits", ctx do
    {:ok, %{path: ballot}} =
      Seshat.household_post(ctx.andrew, %{
        "title" => "Two at once",
        "content" => "Both, now.",
        "ballot" => %{
          "bundle" => [
            %{"setting" => "witness_posts", "value" => "unbounded"},
            %{"setting" => "post_quota", "value" => 40},
            %{"rule" => "Say when you pass."}
          ],
          "term_days" => 7,
          "note" => "small and urgent"
        }
      })

    {:ok, _} = Seshat.household_reply(ctx.andrew, ballot, %{"vote" => "yes"})
    assert %{closed_at: nil} = Gaia.household_ballot_for_thread(ctx.household, ballot)
    assert Gaia.household_beat_shape(ctx.household).witness_rule == "per_beat"

    {:ok, _} = Seshat.household_reply(ctx.wren, ballot, %{"vote" => "yes"})
    assert %{passed: true} = Gaia.household_ballot_for_thread(ctx.household, ballot)
    shape = Gaia.household_beat_shape(ctx.household)
    assert shape.witness_rule == "unbounded" and shape.quota == 40
    assert "Say when you pass." in Gaia.household_contract(ctx.household).in_force.rules

    # The term's own job, later, finds it closed: nothing more.
    Clock.Fake.advance(7 * 86_400)

    assert :ok =
             perform_job(HouseholdBallotWorker, %{"household_id" => ctx.household, "ballot" => 1})
  end

  test "queue_emptied: with nobody waiting, a witness posts again in the beat", ctx do
    {:ok, %{path: ballot}} =
      Seshat.household_post(ctx.andrew, %{
        "title" => "Fair",
        "content" => "When the queue is empty.",
        "ballot" => %{
          "bundle" => [%{"setting" => "witness_posts", "value" => "queue_emptied"}],
          "term_days" => 1,
          "note" => "the fair version"
        }
      })

    for voter <- [ctx.andrew, ctx.wren],
        do: {:ok, _} = Seshat.household_reply(voter, ballot, %{"vote" => "yes"})

    Clock.Fake.advance(86_400)

    assert :ok =
             perform_job(HouseholdBallotWorker, %{"household_id" => ctx.household, "ballot" => 1})

    {:ok, %{path: thread}} = post(ctx, "One")
    # Nobody registered, no turn open: the queue is empty.
    assert {:ok, _} = Seshat.household_reply(ctx.andrew, thread, %{"content" => "Two."})
  end

  # gaia#50: a charter founded with its own settings, in force at once,
  # held to a ballot's checks.
  test "a charter is founded with its own settings and rules, in force at once" do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)

    assert {:error, %{kind: :gaia_beats_invalid}} =
             Seshat.household_propose_contract(andrew, "Ours.", "founding", [
               %{"setting" => "witness_posts", "value" => "always"}
             ])

    assert {:ok, _} =
             Seshat.household_propose_contract(andrew, "Ours.", "founding", [
               %{"setting" => "witness_posts", "value" => "unbounded"},
               %{"rule" => "Be kind."}
             ])

    household = Gaia.household_of(andrew)
    assert Gaia.household_beat_shape(household).witness_rule == "unbounded"

    assert %{
             in_force: %{
               version: 1,
               rules: ["Be kind."],
               settings: %{"witness_posts" => "unbounded"}
             }
           } =
             Gaia.household_contract(household)

    on_exit(fn -> File.rm_rf!(SimaQian.Household.dir(witness.id)) end)
  end
end
