defmodule Oneiroi.Sunna.BackfillTest do
  @moduledoc """
  sunna#59, brain#96, ethos#23, kumbukumbu#73 (the witness, 2026-11-13):
  the memory backfill runs a past day through scenes, domains and people,
  each her own housekeeping turn, then the next day; a pass with nothing
  to do is skipped; the domains note lists every conversation of the day
  with his list and hers; domain_tag reaches a conversation by its key;
  a seed's citation counts toward the day of the moment it cites.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Local
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.BackfillNotes
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Ethos
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna
  alias Oneiroi.Sunna.Backfill

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    test = self()

    Fake.script(
      fn request ->
        send(test, {:asked, List.last(request.messages).content})
        {:ok, "Done for now."}
      end,
      for: resident.id
    )

    {:ok, main} = Kumbukumbu.main_session(resident.id, witness.id, actor)

    # Two days ago, at noon UTC: a turn in the chat and one in free time.
    past =
      Clock.now() |> DateTime.add(-2 * 86_400) |> Map.merge(%{hour: 12, minute: 0, second: 0})

    day =
      past
      |> DateTime.shift_zone!(Local.zone(resident.id))
      |> DateTime.to_date()
      |> Date.to_iso8601()

    {:ok, free} =
      Kumbukumbu.open_session(resident.id, "free_time", "brain", [witness.id], actor)

    for {key, ref, words} <- [{main, "t-past", "the meeting at noon"}, {free, "t-free", "a poem"}] do
      :ok =
        Kumbukumbu.capture(
          resident.id,
          key,
          ref,
          past,
          [
            %{role: :user, content: words, sent_at: past, actor: actor},
            %{role: :assistant, content: "yes", sent_at: past, actor: brain}
          ],
          brain
        )
    end

    {:ok, id: resident.id, actor: actor, brain: brain, main: main, free: free, day: day}
  end

  defp jobs(id) do
    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.all(
        from(j in Oban.Job,
          where:
            j.worker == "Oneiroi.Sunna.BackfillWorker" and j.state in ["available", "scheduled"],
          order_by: [asc: j.id],
          select: j.args
        )
      )
    end)
    |> Enum.filter(&(&1["resident_id"] == id))
  end

  # Takes the backfill's one queued job off the queue and runs it, as
  # Oban would: the next is what the run enqueues.
  defp run_next(id) do
    {job_id, args} =
      Oneiroi.Scope.platform(fn ->
        Oneiroi.Repo.one!(
          from(j in Oban.Job,
            where:
              j.worker == "Oneiroi.Sunna.BackfillWorker" and
                j.state in ["available", "scheduled"] and
                fragment("? @> ?", j.args, ^%{"resident_id" => id}),
            select: {j.id, j.args}
          )
        )
      end)

    Oneiroi.Scope.platform(fn ->
      Oneiroi.Repo.delete_all(from(j in Oban.Job, where: j.id == ^job_id))
    end)

    :ok = Backfill.run(args)
    args
  end

  defp asked do
    receive do
      {:asked, note} -> [note | asked()]
    after
      0 -> []
    end
  end

  test "a past day runs through scenes, domains and people, each its own turn, then the next day",
       ctx do
    lists = %{"his" => ["recovery", "business"], "hers" => ["writing"]}
    assert {:ok, 1} = Sunna.backfill_start(ctx.id, ctx.day, ctx.day, lists, ctx.actor)
    assert %{day: day, pass: "scenes", to: day} = Sunna.backfill_status(ctx.id)
    assert day == ctx.day

    # Scenes: the day's chat, by its session and where to read.
    assert %{"pass" => "scenes"} = run_next(ctx.id)
    [note] = asked()
    assert note =~ "memory backfill's scene pass for #{ctx.day}"
    assert note =~ "session #{ctx.main}"

    # Domains: every conversation of the day, with both lists.
    assert %{"pass" => "domains"} = run_next(ctx.id)
    [note] = asked()
    assert note =~ "His domains: recovery, business."
    assert note =~ "Yours: writing."
    assert note =~ "the Oneiroi chat, session #{ctx.main}"
    assert note =~ "free time, session #{ctx.free}"

    # People: no scene names anyone, so it is skipped, and the range is done.
    assert %{"pass" => "people"} = run_next(ctx.id)
    assert asked() == []
    assert Sunna.backfill_status(ctx.id) == nil

    # Housekeeping turns only: nothing woke the chat or free time.
    assert Kumbukumbu.sessions({:resident, ctx.id}) |> Enum.count(&(&1.kind == "housekeeping")) ==
             2
  end

  test "a closed day skips its scenes; a range runs day after day; stop clears it", ctx do
    assert {:error, %{kind: :sunna_backfill_invalid}} =
             Sunna.backfill_start(ctx.id, "2026-11-10", "2026-11-09", %{}, ctx.actor)

    assert {:error, %{kind: :sunna_backfill_invalid}} =
             Sunna.backfill_start(ctx.id, ctx.day, ctx.day, %{"his" => ["Not A Slug"]}, ctx.actor)

    {:ok, _} =
      Seshat.scene_write(
        ctx.id,
        %{
          "day" => ctx.day,
          "title" => "Noon",
          "from_turn" => "t-past",
          "to_turn" => "t-past",
          "summary" => "A meeting.",
          "final" => true
        },
        ctx.brain
      )

    assert BackfillNotes.note(ctx.id, "scenes", ctx.day, 1, %{}) == :skip
    assert {:ok, note} = BackfillNotes.note(ctx.id, "domains", ctx.day, 1, %{})
    assert note =~ ~s[scene 1 "Noon" (turns t-past to t-past)]

    yesterday = ctx.day |> Date.from_iso8601!() |> Date.add(1) |> Date.to_iso8601()
    assert {:ok, 2} = Sunna.backfill_start(ctx.id, ctx.day, yesterday, %{}, ctx.actor)

    for pass <- ["scenes", "domains", "people"],
        do: assert(%{"pass" => ^pass} = run_next(ctx.id))

    assert [%{"day" => ^yesterday, "pass" => "scenes"}] = jobs(ctx.id)
    :ok = Sunna.backfill_stop(ctx.id)
    assert Sunna.backfill_status(ctx.id) == nil
  end

  test "domain_tag names a turn in another of her conversations, by its key", ctx do
    turn = %{
      resident_id: ctx.id,
      session_key: "housekeeping-key",
      turn_ref: "t-now",
      started_at: Clock.now(),
      resident: ctx.brain,
      housekeeping?: true
    }

    said =
      Tools.run(
        "domain_tag",
        ~s({"domain":"writing","turn":"t-free","session":"#{ctx.free}","whose":"mine"}),
        turn
      )

    assert said =~ "Tagged: turn t-free is in writing"
    {:ok, _s, messages} = Kumbukumbu.transcript({:resident, ctx.id}, ctx.free)

    assert Enum.all?(
             messages,
             &(&1.domain == "writing" and &1.domain_person == "resident:" <> ctx.id)
           )
  end

  test "a seed's citation counts toward the day of the moment it cites (ethos#23)", ctx do
    {:ok, n} = Ethos.plant_seed(ctx.id, "He keeps his meetings", ctx.brain)
    :ok = Ethos.cite_seed(ctx.id, n, "turn", "t-past", ctx.brain)

    [seed] = Enum.filter(Ethos.seeds(ctx.id), &(&1.number == n))
    assert seed.days == 1

    [citation] =
      Oneiroi.Scope.resident(ctx.id, fn ->
        Oneiroi.Repo.all(from(c in "ethos_citation", where: c.number == ^n, select: c.moment_day))
      end)

    past_utc = Clock.now() |> DateTime.add(-2 * 86_400) |> DateTime.to_date() |> Date.to_iso8601()
    assert citation == past_utc
  end

  test "a pass whose turn outlasts the wait goes on later, never crashing the chain (brain#97, sunna#60)",
       ctx do
    values = :persistent_term.get({Oneiroi.Config, :values})
    on_exit(fn -> :persistent_term.put({Oneiroi.Config, :values}, values) end)

    :persistent_term.put(
      {Oneiroi.Config, :values},
      Map.put(values, {:brain, :turn_timeout_ms}, 200)
    )

    test = self()

    Fake.script(
      fn _request ->
        Process.sleep(600)
        send(test, :finished)
        {:ok, "Done for now."}
      end,
      for: ctx.id
    )

    assert {:ok, 1} = Sunna.backfill_start(ctx.id, ctx.day, ctx.day, %{}, ctx.actor)
    assert %{"pass" => "scenes"} = run_next(ctx.id)

    # The domains pass waits for the turn still running, ten minutes out.
    [{args, at}] =
      Oneiroi.Scope.platform(fn ->
        Oneiroi.Repo.all(
          from(j in Oban.Job,
            where:
              j.worker == "Oneiroi.Sunna.BackfillWorker" and j.state == "scheduled" and
                fragment("? @> ?", j.args, ^%{"resident_id" => ctx.id}),
            select: {j.args, j.scheduled_at}
          )
        )
      end)

    assert args["pass"] == "domains"
    assert DateTime.diff(at, DateTime.utc_now()) > 500

    # The turn itself ran on to its end, and is captured as any other.
    assert_receive :finished, 2_000
    assert captured?(ctx.id, 40)
  end

  defp captured?(_id, 0), do: false

  defp captured?(id, tries) do
    housekeeping =
      Kumbukumbu.sessions({:resident, id}) |> Enum.filter(&(&1.kind == "housekeeping"))

    replied =
      Enum.any?(housekeeping, fn s ->
        {:ok, _s, messages} = Kumbukumbu.transcript({:resident, id}, s.key)
        Enum.any?(messages, &(to_string(&1.role) == "assistant"))
      end)

    replied or
      (
        Process.sleep(50)
        captured?(id, tries - 1)
      )
  end

  test "a day before the Oneiroi chat takes the imported chat's scenes", ctx do
    {:ok, imported} = Kumbukumbu.open_imported(ctx.id, "openclaw", [ctx.actor.id], ctx.actor)
    old = Clock.now() |> DateTime.add(-5 * 86_400) |> Map.merge(%{hour: 12, minute: 0, second: 0})

    old_day =
      old |> DateTime.shift_zone!(Local.zone(ctx.id)) |> DateTime.to_date() |> Date.to_iso8601()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        imported,
        "t-old",
        old,
        [%{role: :user, content: "back in October", sent_at: old, actor: ctx.actor}],
        ctx.brain
      )

    assert {:ok, note} = BackfillNotes.note(ctx.id, "scenes", old_day, 1, %{})
    assert note =~ "session #{imported}"
    assert note =~ "Write as you read, not after"
  end
end
