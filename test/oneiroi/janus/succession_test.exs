defmodule Oneiroi.Janus.SuccessionTest do
  @moduledoc """
  A succession's start (janus#3 to #5, agathos-daimon#63,
  sima-qian#67): who may propose, open, decline, withdraw and stop; the
  fork copy made off her yes, a hidden resident no tick, list or witness
  sees, holding her history and her repository as they stood; and the
  backup repository, checked and kept with its token sealed.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Config.Secret
  alias Oneiroi.Fixtures
  alias Oneiroi.Janus
  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Router
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Repos

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    andrew = Actor.new(:witness, witness.id)
    her = Actor.new(:resident, resident.id, "fake/model")
    :ok = AgathosDaimon.write_file(resident.id, "SOUL.md", "# Soul\n\nCurious.", %{}, andrew)
    {:ok, dir} = SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, witness: witness, id: resident.id, andrew: andrew, her: her}
  end

  defp drain,
    do:
      assert(
        %{failure: 0, discard: 0} =
          Oban.drain_queue(queue: :janus_fork, with_safety: false)
      )

  defp tool(ctx, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: "s-1",
        turn_ref: "t-1",
        started_at: Clock.now(),
        resident: ctx.her
      })

  test "the witness proposes; only she opens or declines; one is underway at a time", ctx do
    assert {:ok, %{episode: 1, opened: false}} =
             Janus.propose(
               ctx.id,
               true,
               "a cheaper model, if you want it",
               ctx.andrew
             )

    assert %{state: "proposed", dry_run: true, proposed_by: "witness:" <> _} =
             Janus.succession(ctx.id)

    # She is woken to answer it (janus#33: proposing woke nobody).
    [note] =
      Oneiroi.Scope.platform(fn ->
        Oneiroi.Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Oneiroi.Janus.WakeWorker",
            select: j.args["note"]
          )
        )
      end)

    assert note =~ "Your witness has proposed a dry run of your succession"
    assert note =~ "a cheaper model, if you want it"
    assert note =~ "succession_open"

    assert {:error, %{kind: :janus_underway}} =
             Janus.propose(ctx.id, false, "again", ctx.andrew)

    assert {:error, %{kind: :janus_not_yours}} =
             Janus.open(ctx.id, "for her", ctx.andrew)

    assert tool(ctx, "succession_status", %{}) =~ "a dry run"
    assert tool(ctx, "succession_decline", %{note: "not this season"}) =~ "Declined"
    assert %{state: "declined", ended_note: "not this season"} = Janus.succession(ctx.id)

    # Ended, a new one may be proposed; its proposer withdraws it, she cannot.
    assert {:ok, %{episode: 2}} = Janus.propose(ctx.id, false, "later", ctx.andrew)

    assert {:error, %{kind: :janus_not_yours}} =
             Janus.withdraw(ctx.id, "mine?", ctx.her)

    assert :ok = Janus.withdraw(ctx.id, "not yet", ctx.andrew)
    assert %{episode: 2, state: "withdrawn"} = Janus.succession(ctx.id)

    assert {:error, %{kind: :janus_stage}} =
             Janus.stop(ctx.id, "x", ctx.her)
  end

  test "her yes makes the fork: a hidden copy holding her history and her repository", ctx do
    {:ok, _} = Janus.propose(ctx.id, false, "if you want it", ctx.andrew)
    assert tool(ctx, "succession_open", %{note: "yes, carefully"}) =~ "open"
    assert %{state: "open", opened_note: "yes, carefully"} = Janus.succession(ctx.id)

    # Before the fork is recorded, the witness may make it again (janus#35);
    # she may not, and once it is recorded nobody may.
    assert {:error, %{kind: :janus_not_yours}} = Janus.retry_fork(ctx.id, ctx.her)

    # A recorded failure shows until it is made again, which clears it.
    episode = Janus.succession(ctx.id).episode

    {:ok, _} =
      Router.dispatch(%Commands.FailFork{
        actor: Actor.platform(),
        at: Clock.now(),
        id: ctx.id,
        episode: episode,
        reason: "forks are held"
      })

    assert %{fork_failure: "forks are held"} = Janus.succession(ctx.id)
    assert :ok = Janus.retry_fork(ctx.id, ctx.andrew)
    assert %{fork_failure: nil, state: "open"} = Janus.succession(ctx.id)

    # A second press while the first waits is the same job (2026-11-26:
    # two presses ran two sweeps that blocked each other).
    assert :ok = Janus.retry_fork(ctx.id, ctx.andrew)

    sweeps =
      Oneiroi.Scope.platform(fn ->
        Oneiroi.Repo.all(
          from(j in Oban.Job,
            where:
              j.worker == "Oneiroi.Janus.ForkWorker" and
                fragment("?->>'sweep' = 'true'", j.args) and j.state == "available"
          )
        )
      end)

    assert length(sweeps) == 1

    drain()

    assert {:error, %{kind: :janus_stage}} = Janus.retry_fork(ctx.id, ctx.andrew)

    assert %{state: "forked", copy_id: copy, fork_sequence: seq, fork_events: events} =
             Janus.succession(ctx.id)

    assert is_binary(copy) and seq > 0 and events > 0

    # A fork from its first fold: never active, in no list of his, its
    # source named, and its own stream saying so.
    assert {:ok, %{state: "fork", fork_of: source, account_id: account}} =
             AgathosDaimon.fetch(copy)

    assert source == ctx.id and account == ctx.witness.id
    refute Enum.any?(AgathosDaimon.active_residents(), &(&1.id == copy))
    refute Enum.any?(AgathosDaimon.for_witness(ctx.witness.id), &(&1.id == copy))
    assert Enum.any?(AgathosDaimon.for_witness(ctx.witness.id), &(&1.id == ctx.id))

    # Her repository as it stood, byte for byte.
    assert Repos.tree({:resident, copy}) == Repos.tree({:resident, ctx.id})

    # Her history replayed under the copy: its export is hers, re-keyed.
    {:ok, dir} = SimaQian.repository_dir(copy)
    on_exit(fn -> File.rm_rf!(dir) end)
    mine = Path.join(System.tmp_dir!(), "succession-mine-#{System.unique_integer([:positive])}")
    theirs = Path.join(System.tmp_dir!(), "succession-copy-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(mine) && File.rm_rf!(theirs) end)
    {:ok, _} = Export.write(ctx.id, mine, cutoff: :now)
    {:ok, _} = Export.write(copy, theirs, cutoff: :now)
    {:ok, her_lines} = SimaQian.Rebuild.read_lines(mine)
    {:ok, copy_lines} = SimaQian.Rebuild.read_lines(theirs)
    types = fn lines -> Enum.map(lines, & &1["type"]) end
    assert types.(copy_lines) -- types.(her_lines) == ["Oneiroi.AgathosDaimon.Events.ForkMarked"]

    # A replayed fork job records nothing more; she stops it.
    assert :ok = Janus.Successions.fork(ctx.id, 1, Actor.platform())
    assert %{copy_id: ^copy} = Janus.succession(ctx.id)
    assert tool(ctx, "succession_stop", %{note: "enough"}) =~ "Stopped"

    # Stopped before any nominee met her: the fork goes (janus#28).
    assert %{failure: 0} = Oban.drain_queue(queue: :janus_fork, with_safety: false)
    assert %{fork_discarded_at: %DateTime{}} = Janus.succession(ctx.id)
    assert AgathosDaimon.fetch(copy) == :error
    assert Repos.tree({:resident, copy}) == {:ok, []}

    # And nothing that is not a fork can be discarded.
    assert {:error, %{kind: :sima_qian_not_a_fork}} = SimaQian.discard_fork(ctx.id)
    assert %{state: "stopped"} = Janus.succession(ctx.id)
  end

  test "her own proposal is her yes; nothing of it is exported", ctx do
    assert tool(ctx, "succession_propose", %{note: "I want to try", dry_run: true}) =~
             "open as a dry run"

    assert %{state: "open", dry_run: true, proposed_by: "resident:" <> _} =
             Janus.succession(ctx.id)

    dir = Path.join(System.tmp_dir!(), "succession-x-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, _} = Export.write(ctx.id, dir, cutoff: :now)
    {:ok, lines} = SimaQian.Rebuild.read_lines(dir)
    refute Enum.any?(lines, &String.contains?(&1["type"], "Succession"))
    assert "succession" in Map.keys(Export.not_exported())
  end

  test "the backup is the witness's: checked, kept with its token sealed", ctx do
    {:ok, _} = Janus.propose(ctx.id, false, "if you want it", ctx.andrew)

    assert {:error, %{kind: :sima_qian_remote_invalid}} =
             Janus.set_backup(ctx.id, "not a remote", nil, ctx.andrew)

    assert {:error, %{kind: :janus_not_the_witness}} =
             Janus.set_backup(ctx.id, "/srv/former", nil, ctx.her)

    secret = Secret.wrap("tok-123")

    assert {:ok, %{visibility: "private"}} =
             Janus.set_backup(ctx.id, "/srv/former", secret, ctx.andrew)

    row = Janus.succession(ctx.id)
    assert row.backup_url == "/srv/former"
    refute row.backup_token == "tok-123"
    assert Vault.decrypt(row.backup_token) == {:ok, "tok-123"}
  end
end
