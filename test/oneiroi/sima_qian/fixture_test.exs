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
  `CustodyTransferred`): the ones a witness and the nightly jobs reach
  through the exports today. `ResidentPaused`, `ResidentWoken` and
  `ExportWallSet` have no command edge yet, and `ExportWritten` and
  `BackupCommitted` are `export: false` by design.

  Beside them, an event frozen at an older version than today's, so the
  replay goes through its upcaster: a `SceneWritten` of version 1, from
  before a scene named its people (seshat#57). It re-exports at today's
  version with the upcaster's value, which `@upcast` states; every other
  line re-exports byte for byte.
  """
  use Oneiroi.DataCase, async: false

  alias Commanded.Event.Upcaster
  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Export

  @fixture Path.expand("../../fixtures/sima_qian", __DIR__)

  # A line frozen at an older version: its type and version, and the
  # version and data fields the replay re-exports it with.
  @upcast %{
    {"Oneiroi.Seshat.Events.SceneWritten", 1} => {2, %{"people" => []}}
  }

  defp declared do
    for system <- Oneiroi.Boot.components(),
        Code.ensure_loaded?(system),
        function_exported?(system, :events, 0),
        pair <- system.events(),
        into: %{},
        do: pair
  end

  # The line as today's export writes it: unchanged, or for an upcast
  # one the decoded line at its new version with the upcaster's fields.
  defp today(line) do
    decoded = Jason.decode!(line)

    case @upcast[{decoded["type"], decoded["version"]}] do
      nil ->
        line

      {version, fields} ->
        %{decoded | "version" => version, "data" => Map.merge(decoded["data"], fields)}
    end
  end

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
    declared = declared()
    lines = fixture_lines()

    assert Enum.any?(lines, &Map.has_key?(@upcast, type_version(&1))),
           "the fixture carries no line at an older version, so no upcaster is replayed"

    for line <- lines, decoded = Jason.decode!(line) do
      module = String.to_existing_atom("Elixir." <> decoded["type"])
      assert Map.has_key?(declared, module), "#{decoded["type"]} is in no system's events/0"
      assert module.__version__() == declared[module]

      assert module.__version__() == decoded["version"] or
               Upcaster.impl_for(struct(module)) != Upcaster.Any,
             "#{decoded["type"]} v#{decoded["version"]} in the fixture, v#{module.__version__()} now, and no upcaster"

      if decoded["version"] != module.__version__() do
        now = module.__version__()

        assert {^now, _fields} = @upcast[{decoded["type"], decoded["version"]}],
               "#{decoded["type"]} v#{decoded["version"]} is upcast with no line in @upcast saying to what"
      end
    end
  end

  defp type_version(line) do
    decoded = Jason.decode!(line)
    {decoded["type"], decoded["version"]}
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
    importer = Actor.new(:witness, b.id)

    assert {:ok, %{id: id, attestation: :none, events: 9}} =
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
    replayed = Enum.take(exported, length(fixture))
    assert length(replayed) == length(fixture)

    for {got, line} <- Enum.zip(replayed, fixture) do
      case today(line) do
        ^line -> assert got == line
        upcast -> assert Jason.decode!(got) == upcast
      end
    end

    assert [imported, _custody] =
             exported |> Enum.drop(length(fixture)) |> Enum.map(&Jason.decode!/1)

    assert imported["data"]["attestation"] == "none"
    assert imported["data"]["source"] == repo
  end
end
