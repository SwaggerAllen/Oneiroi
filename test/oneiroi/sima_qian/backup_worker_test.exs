defmodule Oneiroi.SimaQian.BackupWorkerTest do
  @moduledoc "The nightly backup reads every resident's result: a failure is logged with its site and fails the job."
  use Oneiroi.DataCase, async: false

  import ExUnit.CaptureLog

  # 2026-11-01: Lily's first backup after her import exported, failed before
  # its commit landed, and the job was marked completed with nothing logged.

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.AttestationWorker
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.BackupWorker
  alias Oneiroi.SimaQian.Git

  setup do
    a = Fixtures.account!()
    actor = Actor.new(:witness, a.id)
    good = Fixtures.resident!(a)
    bad = Fixtures.resident!(a)

    bare =
      Path.join(System.tmp_dir!(), "oneiroi-worker-bare-#{System.unique_integer([:positive])}")

    :ok = Git.init_bare(bare)
    :ok = Oneiroi.SimaQian.set_remote(good.id, bare, nil, actor)
    # A remote nothing answers at: the push fails, after the export.
    :ok = Oneiroi.SimaQian.set_remote(bad.id, "/nonexistent/oneiroi-remote.git", nil, actor)

    on_exit(fn ->
      File.rm_rf!(bare)
      File.rm_rf!(Backup.dir(good.id))
      File.rm_rf!(Backup.dir(bad.id))
    end)

    Clock.Fake.advance(120)
    {:ok, good: good, bad: bad}
  end

  test "a failed resident is logged with its site, the others land, and the job fails", ctx do
    log =
      capture_log(fn ->
        send(self(), {:result, BackupWorker.run(%{})})
      end)

    assert_received {:result, {:error, error}}
    assert %{kind: :sima_qian_backup_failed, site: :sima_qian_nightly_backup_failed} = error
    assert error.details[:residents] == [ctx.bad.id]
    assert error.details[:sites] == [:sima_qian_git_run_failed]

    assert log =~ "the nightly backup failed for resident #{ctx.bad.id}"
    refute log =~ "resident #{ctx.good.id}"

    good = Scope.platform(fn -> Store.get(ctx.good.id) end)
    assert is_binary(good.last_backup_commit)
  end

  test "every resident landing is :ok", ctx do
    other =
      Path.join(System.tmp_dir!(), "oneiroi-worker-bare2-#{System.unique_integer([:positive])}")

    :ok = Git.init_bare(other)
    on_exit(fn -> File.rm_rf!(other) end)
    :ok = Oneiroi.SimaQian.set_remote(ctx.bad.id, other, nil, Actor.new(:job, "t"))

    assert :ok == BackupWorker.run(%{})
  end

  test "the attestation reads its results the same way" do
    assert :ok == AttestationWorker.run(%{})
  end
end
