defmodule Oneiroi.SimaQian.WholeTest do
  @moduledoc """
  A rebuild restores the whole resident (sima-qian #20): every stream
  that is the resident's is exported, merged in the order it was
  written, and replayed into a new resident in that order, so the copy
  re-exports line for line and reads back the same transcripts,
  bookmarks, judgement, journal, figures and spend. Rebuilding beside
  the source in one store leaves the source's own export untouched,
  which is the guard on every projector writing only its own resident's
  rows (sima-qian #21).
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Eunomia
  alias Oneiroi.Fixtures
  alias Oneiroi.HuginnMuninn
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian
  alias Oneiroi.SimaQian.Backup
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Rebuild
  alias Oneiroi.Sunna

  setup do
    a = Fixtures.account!()
    b = Fixtures.account!()
    r = Fixtures.resident!(a)
    actor = Actor.new(:witness, a.id)
    brain = Actor.new(:resident, r.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(a.id, "sk-or-test", actor)
    Model.clear()
    Honcho.clear(for: r.id)
    bare = Path.join(System.tmp_dir!(), "oneiroi-whole-#{System.unique_integer([:positive])}")
    out = Path.join(System.tmp_dir!(), "oneiroi-whole-out-#{System.unique_integer([:positive])}")
    src = Path.join(System.tmp_dir!(), "oneiroi-whole-src-#{System.unique_integer([:positive])}")
    :ok = Git.init_bare(bare)
    on_exit(fn -> Enum.each([Backup.dir(r.id), bare, out, src], &File.rm_rf!/1) end)
    on_exit(fn -> Model.clear(for: r.id) end)
    {:ok, a: a, b: b, r: r, actor: actor, brain: brain, bare: bare, out: out, src: src}
  end

  defp lines(dir) do
    [dir, "records", "events", "*.jsonl"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&(&1 |> File.read!() |> String.split("\n", trim: true)))
  end

  # A life across the streams: a turn (the conversation and the
  # ledger), a bookmark and a tag (memory), a position and a prediction
  # (judgement), a journal entry (the journal and the schedule's day), a
  # check-in (the schedule), a counter (the audits) and a document (the
  # library).
  defp live!(ctx) do
    id = ctx.r.id
    {:ok, key} = Kumbukumbu.main_session(id, ctx.a.id, ctx.actor)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, key, "shall we bake?", ctx.actor)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: key, anchor_ref: ref, line: "the first bake", summary: "We baked."},
        ctx.brain
      )

    :ok = Kumbukumbu.create_tag(id, "bread", ctx.actor)
    :ok = Kumbukumbu.apply_tag(id, "bread", "bookmark", n, ctx.actor)
    {:ok, _} = Eunomia.take_position(id, "Rye first.", %{session_key: key}, ctx.brain)

    {:ok, _} =
      Eunomia.log_prediction(id, "It rises.", ~U[2026-11-01 00:00:00Z], %{}, ctx.brain)

    {:ok, _} = Seshat.journal_add(id, nil, "note", "Baked rye.", ctx.brain)
    {:ok, _} = Sunna.set_checkin(id, "morning", "morning", "09:00", ctx.actor)
    :ok = HuginnMuninn.define_counter(id, "loaves", "Loaves", ctx.actor)
    :ok = HuginnMuninn.increment(id, "loaves", 2, "two", ctx.actor)
    {:ok, _} = Seshat.write(id, "writing/rye.md", "# Rye\n\nSlow.", ctx.brain)
    key
  end

  test "every stream comes back: the copy re-exports line for line and reads back the same life, and the source is untouched",
       ctx do
    key = live!(ctx)
    id = ctx.r.id

    # And a regression run whose card keeps a trace (eunomia #31): the
    # trial calls a read and a write with words unique to it. The stream
    # is sealed (eunomia #9), so none of it may come back.
    unique = "sandpiper-" <> Integer.to_string(System.unique_integer([:positive]))
    test_texts = %{prompt: "Say #{unique}.", passes_if: "says it", fails_if: "does not"}
    {:ok, 1} = Eunomia.write_test(id, test_texts, ctx.actor)

    Model.calls(
      [
        %{name: "transcript_search", arguments: %{q: "bake"}},
        %{name: "bookmark_add", arguments: %{line: unique, summary: unique}}
      ],
      "I say #{unique}.",
      for: id
    )

    {:ok, run} = Eunomia.run(id, ["m1"], :all, ctx.actor)

    assert %{failure: 0, discard: 0} =
             Oban.drain_queue(queue: :eunomia_regression, with_safety: false)

    assert {:ok, _, [%{trace: [%{"kind" => "read"}, %{"kind" => "mocked"} = write]}], _} =
             Eunomia.run_detail(id, run)

    assert write["arguments"] =~ unique

    :ok = SimaQian.set_remote(id, ctx.bare, nil, ctx.actor)
    Clock.Fake.advance(120)
    {:ok, _} = SimaQian.backup(id, ctx.actor)
    source = lines(Backup.dir(id))

    names = source |> Enum.map(&Jason.decode!(&1)["stream"]) |> Enum.uniq()

    # In the order written, across streams: the resident before anything
    # of hers, the turn before the bookmark on it.
    types = Enum.map(source, &Jason.decode!(&1)["type"])
    assert hd(types) == "Oneiroi.AgathosDaimon.Events.ResidentCreated"

    assert Enum.find_index(types, &(&1 == "Oneiroi.Kumbukumbu.Events.TurnCaptured")) <
             Enum.find_index(types, &String.ends_with?(&1, "BookmarkAdded"))

    for name <- ~w(resident conversation memory judgement journal schedule audits library ledger) do
      assert Enum.any?(names, &(Export.prefix(&1) == name)),
             "no #{name} line in #{inspect(names)}"
    end

    assert ("conversation-" <> key) in names
    refute Enum.any?(names, &(Export.prefix(&1) in ["honcho", "regression", "account"]))
    refute Enum.any?(source, &(&1 =~ id))
    refute Enum.any?(source, &(&1 =~ unique))
    refute Enum.any?(source, &(&1 =~ "AnswerRecorded"))

    importer = Actor.new(:witness, ctx.b.id)
    assert {:ok, %{id: copy}} = SimaQian.rebuild(ctx.bare, ctx.b.id, importer)
    on_exit(fn -> File.rm_rf!(Backup.dir(copy)) end)

    # The source, exported again after the copy replayed beside it, is
    # what it was: no replayed event wrote the source's rows.
    Clock.Fake.advance(120)
    {:ok, _} = Export.write(id, ctx.src)
    assert lines(ctx.src) == source

    # The copy re-exports the source's lines, then its own.
    {:ok, _} = Export.write(copy, ctx.out)
    rebuilt = lines(ctx.out)
    assert Enum.take(rebuilt, length(source)) == source

    assert rebuilt |> Enum.drop(length(source)) |> Enum.map(&Jason.decode!(&1)["type"]) == [
             "Oneiroi.AgathosDaimon.Events.Imported",
             "Oneiroi.AgathosDaimon.Events.CustodyTransferred"
           ]

    # And reads back the same life.
    said = fn rid -> {:ok, _, ms} = Kumbukumbu.transcript({:resident, rid}, key) end

    assert Enum.map(said.(copy) |> elem(2), & &1.content) ==
             Enum.map(said.(id) |> elem(2), & &1.content)

    assert [%{line: "the first bake", tags: ["bread"]}] = Kumbukumbu.bookmarks(copy)
    assert [%{statement: "Rye first."}] = Eunomia.positions(copy)
    assert %{open: [%{statement: "It rises."}]} = Eunomia.predictions(copy)
    assert %{entries: [%{text: "Baked rye."}]} = Seshat.journal_day(copy, Sunna.today(id).day)

    assert [%{key: "loaves", value: 2}] =
             HuginnMuninn.figures(copy) |> Enum.filter(&(&1.key == "loaves"))

    assert Enum.any?(Seshat.documents(copy), &(&1.path == "writing/rye.md"))

    # The run, its cards and their traces stayed behind, and so did its
    # bill: regression spend is the witness's view alone (nisaba #4), so
    # a rebuild restores everything else of the spend and none of that.
    assert [] = Eunomia.runs(copy)
    assert [] = Eunomia.tests(copy)

    spend = fn rid ->
      rid
      |> Oneiroi.Nisaba.spend(:witness, :purpose, ~U[2026-01-01 00:00:00Z])
      |> Enum.reject(&(&1.key == "regression"))
    end

    assert spend.(copy) == spend.(id)
  end

  test "a line naming a stream the export never carries is refused before anything is written" do
    id = Ecto.UUID.generate()

    line = %{
      "sequence" => 1,
      "stream" => "account",
      "type" => "Oneiroi.Gaia.Events.AccountCreated",
      "version" => 1,
      "at" => "2026-10-26T12:00:00Z",
      "actor" => %{"kind" => "platform", "id" => nil, "model" => nil},
      "data" => %{"id" => "$self"}
    }

    assert {:error, %Error{kind: :sima_qian_stream_refused, details: [stream: "account"]}} =
             Rebuild.append(id, [line])

    assert {:error, :stream_not_found} = Oneiroi.EventStore.read_stream_forward("account-" <> id)
  end

  test "every router's stream is exported or excluded with its reason, and neither list names a stream no router writes" do
    {:ok, modules} = :application.get_key(:oneiroi, :modules)

    prefixes =
      for m <- modules,
          Code.ensure_loaded?(m) and function_exported?(m, :__stream_prefix__, 0),
          into: MapSet.new(),
          do: String.trim_trailing(m.__stream_prefix__(), "-")

    exported = MapSet.new(Export.streams())
    excluded = MapSet.new(Map.keys(Export.not_exported()))

    assert MapSet.disjoint?(exported, excluded)
    assert MapSet.union(exported, excluded) == prefixes

    # The sealed streams stay on the excluded side by name: the regression
    # stream carries every card and its trace (eunomia #9, #31), and its
    # events' own `export: false` must not be the only thing keeping them.
    assert "regression" in excluded
  end
end
