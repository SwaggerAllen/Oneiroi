defmodule Oneiroi.SimaQian.DryRunTest do
  @moduledoc "The import rehearsed (sima-qian #18): the import and a first backup on a Lily-shaped repository, reported by name and count and never by content."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.DryRun
  alias Oneiroi.SimaQian.Import

  # A line no report may ever carry: it stands for her words.
  @private "a sentence only the repository holds"

  setup do
    witness = Fixtures.account!()
    actor = Actor.new(:witness, witness.id)

    source =
      Path.join(System.tmp_dir!(), "oneiroi-dry-run-src-#{System.unique_integer([:positive])}")

    File.mkdir_p!(source)
    on_exit(fn -> File.rm_rf!(source) end)
    {:ok, witness: witness, actor: actor, source: source}
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    out
  end

  defp write!(source, path, content) do
    full = Path.join(source, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
  end

  test "a Lily-shaped repository: imported, backed up, and reported by name and count only",
       ctx do
    s = ctx.source
    git!(s, ["init", "-q", "-b", "main"])
    write!(s, "SOUL.md", "# Lily\n\n#{@private}\n\nAnd another line.")
    write!(s, "USER.md", "# David\n")
    write!(s, "DREAMS.md", @private)
    write!(s, "writing/essay.md", "# The essay\n\n#{@private}")
    write!(s, "research/2026-10-22-1/notes.md", "# Notes\n\nTwelve bytes.")
    # David's records, translated by the import (sima-qian #19): her
    # words go into her records here and never into the report.
    write!(
      s,
      "records/transcripts/2026/10/2026-10-20.jsonl",
      ~s({"sentAt":"2026-10-20T10:00:00.000Z","agentId":"lily","sessionKey":"agent:lily:main","runKind":"user","role":"user","content":"#{@private}"}\n) <>
        ~s({"sentAt":"2026-10-20T10:00:03.000Z","agentId":"lily","sessionKey":"agent:lily:main","runKind":"user","role":"assistant","content":"#{@private}"}\n)
    )

    write!(
      s,
      "records/bookmarks.jsonl",
      ~s({"id":1,"line":"#{@private}","summary":"#{@private}","sessionKey":"agent:lily:main","spanStart":"2026-10-20T10:00:00.000Z","spanEnd":"2026-10-20T10:00:03.000Z","pinnedBy":null,"pinnedAt":null,"createdAt":"2026-10-20T10:05:00.000Z","tags":[]}\n)
    )

    write!(s, "records/README.md", @private)
    write!(s, "honcho/lily-peer-card.md", @private)
    git!(s, ["add", "-A"])
    git!(s, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "hers"])

    assert {:ok, report} =
             DryRun.run(s, %{name: "Lily", slug: "lily-rehearsed"}, ctx.witness.id, ctx.actor)

    on_exit(fn -> File.rm_rf!(Backup.dir(report.import.id)) end)

    assert %{seeded: ["SOUL.md", "USER.md"], adopted: 2, events: 0} = report.import
    assert report.soul_lines == 2

    assert "records/README.md" in report.import.not_transferred and
             "DREAMS.md" in report.import.not_transferred

    refute "records" in report.import.not_transferred

    assert %{source: "David", counts: %{"sessions" => 1, "messages" => 2, "bookmarks" => 1}} =
             report.import.translated

    assert report.shape.unread == ["honcho/lily-peer-card.md"]

    assert %{folder: "research", files: 1} =
             Enum.find(report.shape.folders, &(&1.folder == "research"))

    assert %{commits: [_ | _]} = report.backup

    text = DryRun.markdown({:ok, report})
    assert text =~ "# IMPORT DRY RUN: ok"
    assert String.ends_with?(text, "# IMPORT DRY RUN: ok")
    assert text =~ "## Translated from David's records"
    assert text =~ "| bookmarks | 1 |"
    assert text =~ "| messages | 2 |"
    assert text =~ "- `records/README.md`: a record nothing here reads"
    assert text =~ "## Every file under the folders, accounted"
    assert text =~ "2 adopted, 0 left behind with a reason (0 of them unaccounted)"
    assert text =~ "## Under `honcho/`, read by nothing"
    assert text =~ "| Soul lines minted | 2 |"
    refute text =~ @private
  end

  test "a failed import is reported as the step that failed, verdict first and last", ctx do
    # An empty directory has no `main` branch to clone.
    assert {:error, report} =
             DryRun.run(ctx.source, %{name: "Lily", slug: "lily-none"}, ctx.witness.id, ctx.actor)

    assert report.failed == :import
    text = DryRun.markdown({:error, report})
    assert text =~ "# IMPORT DRY RUN: FAILED at import"
    assert String.ends_with?(text, "# IMPORT DRY RUN: FAILED at import")
  end

  test "the task refuses a store with a resident, and a provider that is not the in-memory one" do
    task = Mix.Tasks.Oneiroi.Import.DryRun
    fake = Oneiroi.Nisaba.Provider.Fake
    assert task.refusal(fake, []) == nil
    assert task.refusal(fake, [%{kind: "resident"}]) =~ "already holds a resident"
    assert task.refusal(Oneiroi.Nisaba.Provider.OpenRouter, []) =~ "NISABA_PROVIDER must be fake"
  end

  # The rehearsal of 2026-10-31 passed with one of Lily's files neither
  # adopted nor named. No real repository reaches this while every case
  # has a rule, so the adoption is handed in missing a file.
  test "a file the adoption neither took nor refused is unaccounted, named, and fails the rehearsal" do
    dir = Path.join(System.tmp_dir!(), "oneiroi-account-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    write!(dir, "wiki/seen.md", "x")
    write!(dir, "wiki/missed.md", "x")
    write!(dir, "wiki/.hidden/log.jsonl", "x")

    ledger =
      Import.account(dir, nil, %{kept: []}, %{
        adopted: ["wiki/seen.md"],
        skipped: []
      })

    assert ledger.unaccounted == ["wiki/missed.md"]

    assert [
             {"wiki/.hidden/log.jsonl", "a hidden name, which the library does not hold"},
             {"wiki/missed.md", "missed by the library's adoption" <> _}
           ] = ledger.left_behind

    report = %{import: %{unaccounted: ledger.unaccounted}}
    assert {:error, %{failed: :accounting}} = DryRun.accounted({:ok, report})
    assert {:ok, _} = DryRun.accounted({:ok, %{import: %{unaccounted: []}}})
  end
end
