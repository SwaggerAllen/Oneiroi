defmodule Oneiroi.SimaQian.ExportTest do
  @moduledoc "An unchanged store exports identical bytes; the resident's id never appears (plan P0.7)."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Export

  @keys ["sequence", "stream", "type", "version", "at", "actor", "data"]

  setup do
    a = Fixtures.account!()
    r = Fixtures.resident!(a)
    actor = Actor.new(:witness, a.id)
    {:ok, 1} = Oneiroi.AgathosDaimon.mint_id(r.id, "bookmark", actor)
    {:ok, 2} = Oneiroi.AgathosDaimon.mint_id(r.id, "bookmark", actor)
    dir = Path.join(System.tmp_dir!(), "oneiroi-export-#{System.unique_integer([:positive])}")
    working = Backup.dir(r.id)

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm_rf!(working)
    end)

    {:ok, r: r, a: a, actor: actor, dir: dir}
  end

  defp lines(dir, day \\ "2026-10-26") do
    dir
    |> Path.join("records/events/#{day}.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  test "the identity files land at the repository root as last written", %{
    r: r,
    actor: actor,
    dir: dir
  } do
    :ok =
      Oneiroi.AgathosDaimon.write_file(r.id, "SOUL.md", "# Soul\n", %{origin: "authored"}, actor)

    :ok =
      Oneiroi.AgathosDaimon.write_file(r.id, "USER.md", "# You\n", %{origin: "uploaded"}, actor)

    :ok =
      Oneiroi.AgathosDaimon.write_file(
        r.id,
        "SOUL.md",
        "# Soul\n\nRevised.\n",
        %{origin: "authored"},
        actor
      )

    Clock.Fake.advance(120)

    assert {:ok,
            %{
              files: [
                "SOUL.md",
                "USER.md",
                "honcho/custom-instructions.md",
                "records/README.md" | _
              ]
            }} =
             Export.write(r.id, dir)

    # The soul lands rendered with its line markers (agathos-daimon #27).
    assert File.read!(Path.join(dir, "SOUL.md")) == "# Soul\n\n[soul/1] Revised.\n"
    assert File.read!(Path.join(dir, "USER.md")) == "# You\n"
  end

  test "identical bytes twice, keys in order, lines numbered from 1, the id as $self", %{
    r: r,
    dir: dir
  } do
    Clock.Fake.advance(120)

    assert {:ok,
            %{
              through: 3,
              files: [
                "honcho/custom-instructions.md",
                "records/README.md",
                "records/events/2026-10-26.jsonl"
              ]
            }} =
             Export.write(r.id, dir)

    first = File.read!(Path.join(dir, "records/events/2026-10-26.jsonl"))
    assert {:ok, _} = Export.write(r.id, dir)
    assert File.read!(Path.join(dir, "records/events/2026-10-26.jsonl")) == first

    lines = lines(dir)
    assert length(lines) == 3
    refute first =~ r.id
    assert first =~ "$self"

    for {line, n} <- Enum.with_index(lines, 1) do
      decoded = Jason.decode!(line, objects: :ordered_objects)
      assert Enum.map(decoded.values, &elem(&1, 0)) == @keys
      assert decoded["sequence"] == n
      assert decoded["stream"] == "resident"
      assert decoded["version"] == 1
      assert decoded["actor"]["kind"] in ["platform", "witness"]
    end

    assert [created, minted, _] = Enum.map(lines, &Jason.decode!/1)
    assert created["type"] == "Oneiroi.AgathosDaimon.Events.ResidentCreated"
    assert created["data"]["id"] == "$self"
    assert created["data"]["slug"] == r.slug
    assert minted["data"] == %{"id" => "$self", "kind" => "bookmark", "number" => 1}
  end

  test "the watermark holds back what may still be being written", %{r: r, dir: dir} do
    assert {:ok, %{through: 0, files: ["honcho/custom-instructions.md", "records/README.md"]}} =
             Export.write(r.id, dir)

    refute File.exists?(Path.join(dir, "records/events/2026-10-26.jsonl"))
    Clock.Fake.advance(61)
    assert {:ok, %{through: 3}} = Export.write(r.id, dir)
  end

  test "days split by the event's own instant", %{r: r, dir: dir, actor: actor} do
    Clock.Fake.advance(86_400)
    {:ok, 3} = Oneiroi.AgathosDaimon.mint_id(r.id, "bookmark", actor)
    Clock.Fake.advance(120)

    assert {:ok, %{through: 4, files: [_instructions, "records/README.md", first, second]}} =
             Export.write(r.id, dir)

    assert first == "records/events/2026-10-26.jsonl"
    assert second == "records/events/2026-10-27.jsonl"
    assert length(lines(dir, "2026-10-26")) == 3
    assert [line] = lines(dir, "2026-10-27")
    assert Jason.decode!(line)["sequence"] == 4
  end

  test "a redacted field is written as null and its plaintext is nowhere", %{
    r: r,
    dir: dir,
    actor: actor
  } do
    :ok =
      Oneiroi.SimaQian.set_remote(r.id, "https://example.invalid/lily.git", "ghp_secret", actor)

    Clock.Fake.advance(120)
    assert {:ok, %{through: 4}} = Export.write(r.id, dir)
    body = File.read!(Path.join(dir, "records/events/2026-10-26.jsonl"))
    refute body =~ "ghp_secret"
    assert [_, _, _, remote] = Enum.map(lines(dir), &Jason.decode!/1)
    assert remote["type"] == "Oneiroi.AgathosDaimon.Events.RecordsRemoteSet"
    assert remote["data"]["url"] == "https://example.invalid/lily.git"
    assert remote["data"]["token_ciphertext"] == nil
  end

  test "the export's own bookkeeping stays in the log and out of the export", %{
    r: r,
    dir: dir,
    actor: actor
  } do
    Clock.Fake.advance(120)
    assert {:ok, %{through: 3}} = Oneiroi.SimaQian.backup(r.id, actor)
    Clock.Fake.advance(120)
    assert {:ok, %{through: 5}} = Export.write(r.id, dir)
    assert length(lines(dir)) == 3

    assert {:ok, [_, _, _, written, committed]} =
             Oneiroi.EventStore.read_stream_forward("resident-" <> r.id)

    assert %Oneiroi.AgathosDaimon.Events.ExportWritten{through: 3} = written.data
    assert %Oneiroi.AgathosDaimon.Events.BackupCommitted{sequence: 3} = committed.data
  end
end
