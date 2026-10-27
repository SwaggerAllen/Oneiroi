defmodule Oneiroi.SimaQian.FixtureTest do
  @moduledoc """
  The checked-in log, `test/fixtures/sima_qian/records/events/*.jsonl`, is a
  resident's export frozen at the event shapes of the day it was written.
  It replays through the rebuild into today's store and re-exports line
  for line, which is the upcaster guard conventions §6 asks for: a shape
  change is a new version with an upcaster, and this is the test that
  fails when the upcaster is missing.

  Six of the eleven resident events are in it (`ResidentCreated`,
  `IdMinted`, `RecordsRemoteSet`, `RootMismatchDetected`, `Imported`,
  `CustodyTransferred`): the ones a steward and the nightly jobs reach
  through the exports today. `ResidentPaused`, `ResidentWoken` and
  `ExportWallSet` have no command edge yet, and `ExportWritten` and
  `BackupCommitted` are `export: false` by design.
  """
  use Oneiroi.DataCase, async: false

  alias Commanded.Event.Upcaster
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Export

  @fixture Path.expand("../../fixtures/sima_qian", __DIR__)

  defp fixture_lines do
    [@fixture, "records", "events", "*.jsonl"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path -> path |> File.read!() |> String.split("\n", trim: true) end)
  end

  defp git!(dir, args) do
    identity = ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid"]
    {out, 0} = System.cmd("git", identity ++ args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end

  test "every line names a declared event at a version the store still reads" do
    declared = Oneiroi.AgathosDaimon.events() |> Map.new()

    for line <- fixture_lines(), decoded = Jason.decode!(line) do
      module = String.to_existing_atom("Elixir." <> decoded["type"])
      assert Map.has_key?(declared, module), "#{decoded["type"]} is not in Resident.events/0"
      assert module.__version__() == declared[module]

      assert module.__version__() == decoded["version"] or
               Upcaster.impl_for(struct(module)) != nil,
             "#{decoded["type"]} v#{decoded["version"]} in the fixture, v#{module.__version__()} now, and no upcaster"
    end
  end

  test "the fixture replays into today's store and re-exports line for line" do
    repo = Path.join(System.tmp_dir!(), "oneiroi-fixture-#{System.unique_integer([:positive])}")

    out =
      Path.join(System.tmp_dir!(), "oneiroi-fixture-out-#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo)
    File.cp_r!(Path.join(@fixture, "records"), Path.join(repo, "records"))
    git!(repo, ["init", "-q", "-b", "main"])
    git!(repo, ["add", "-A"])
    git!(repo, ["commit", "-q", "-m", "the fixture, with no trailers"])

    # The fixture's own instants run into 2026-10-27; the clock must be past
    # them before the import, or the watermark holds the lines back and the
    # import's own events land on an earlier day than the lines they follow.
    Clock.Fake.advance(3 * 86_400)
    b = Fixtures.account!()
    importer = Actor.new(:steward, b.id)

    assert {:ok, %{id: id, attestation: :none, events: 8}} =
             Oneiroi.SimaQian.rebuild(repo, b.id, importer)

    on_exit(fn -> Enum.each([repo, out, Backup.dir(id)], &File.rm_rf!/1) end)

    Clock.Fake.advance(120)
    assert {:ok, %{through: 10}} = Export.write(id, out)

    exported =
      [out, "records", "events", "*.jsonl"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(fn path -> path |> File.read!() |> String.split("\n", trim: true) end)
      |> Enum.sort_by(&Jason.decode!(&1)["sequence"])

    fixture = fixture_lines()
    assert Enum.take(exported, length(fixture)) == fixture

    assert [imported, _custody] =
             exported |> Enum.drop(length(fixture)) |> Enum.map(&Jason.decode!/1)

    assert imported["data"]["attestation"] == "none"
    assert imported["data"]["source"] == repo
  end
end
