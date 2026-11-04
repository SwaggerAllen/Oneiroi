defmodule Oneiroi.Kumbukumbu.RankedMemoryTest do
  @moduledoc """
  Ranked memory (kumbukumbu#45, #47; design/memory-weighting.md): the
  pins in the stable prefix, the index ranked against the turn's words
  with the learned edges out of its seed and a fifth drawn at random,
  and the edges learned from what was returned and what helped, with
  the resident's amendments (Position #45): no rule from the ranker's
  own cut, co-return written from the seed alone, a correction never
  taking a negative.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Edges
  alias Oneiroi.Kumbukumbu.Ranking
  alias Oneiroi.Kumbukumbu.Store
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Export

  describe "the arithmetic" do
    test "a weight decays to half in a half-life and is softly bounded either way" do
      t0 = ~U[2026-11-01 00:00:00Z]
      assert_in_delta Edges.decayed(0.8, t0, DateTime.add(t0, 30, :day), 30), 0.4, 1.0e-9
      assert Edges.decayed(0.8, t0, t0, 30) == 0.8

      up = Enum.reduce(1..200, 0.0, fn _, w -> Edges.bump(w, 0.15) end)
      down = Enum.reduce(1..200, 0.0, fn _, w -> Edges.bump(w, -0.05) end)
      assert up < 1.0 and up > 0.99
      assert down > -1.0 and down < -0.99
    end

    test "co-return runs from the seed alone, and never to itself" do
      assert Edges.co_returned([1, 2], [1, 3], 0.05) == [{1, 3, 0.05}, {2, 1, 0.05}, {2, 3, 0.05}]
    end

    test "use: the used toward each other, toward the ignored a step down, never against a correction" do
      changes = Edges.used([1, 2], [1, 2, 3, 4], MapSet.new([4]), 0.05, 0.15)

      assert {1, 2, 0.15} in changes and {2, 1, 0.15} in changes
      assert {1, 3, -0.05} in changes and {2, 3, -0.05} in changes
      refute Enum.any?(changes, fn {_from, to, delta} -> to == 4 and delta < 0 end)
      refute Enum.any?(changes, fn {from, to, _delta} -> from == to end)
    end
  end

  describe "the ranking" do
    defp b(n),
      do: %{
        number: n,
        line: "memory #{n}",
        anchor_at: ~U[2026-11-01 00:00:00Z],
        tags: [],
        pinned_at: nil
      }

    defp rank(candidates, edges, draw, opts \\ []) do
      Ranking.rank(
        candidates,
        edges,
        Keyword.merge(
          [
            now: ~U[2026-11-03 00:00:00Z],
            lambda: 0.3,
            half_life: 30,
            lines: 3,
            explore: 1,
            seeds: 1,
            min_score: 0.0,
            budget: 1500,
            draw: draw
          ],
          opts
        )
      )
    end

    test "the seed is the nearest; an edge out of it lifts a farther candidate over a nearer one" do
      candidates = [
        %{bookmark: b(1), distance: 0.1},
        %{bookmark: b(2), distance: 0.3},
        %{bookmark: b(3), distance: 0.35}
      ]

      plain = rank(candidates, [], [])
      assert plain.seeds == [1]
      assert Enum.map(plain.ranked, & &1.bookmark.number) == [1, 2]

      edge = %{from_number: 1, to_number: 3, w: 0.5, touched_at: ~U[2026-11-03 00:00:00Z]}
      lifted = rank(candidates, [edge], [])
      assert Enum.map(lifted.ranked, & &1.bookmark.number) == [1, 3]
      assert [%{bookmark: %{number: 2}, why: "past the index's ranked lines"}] = lifted.rejected
    end

    test "the draw comes from outside the ranked set, and a near-miss it draws is explored, not rejected" do
      candidates = [
        %{bookmark: b(1), distance: 0.1},
        %{bookmark: b(2), distance: 0.2},
        %{bookmark: b(3), distance: 0.3}
      ]

      ranked = rank(candidates, [], [b(1), b(3), b(9)])
      assert Enum.map(ranked.ranked, & &1.bookmark.number) == [1, 2]
      assert Enum.map(ranked.explored, & &1.bookmark.number) == [3]
      assert ranked.rejected == []
    end

    test "the line rejects what scores under it" do
      candidates = [%{bookmark: b(1), distance: 0.1}, %{bookmark: b(2), distance: 0.9}]
      ranked = rank(candidates, [], [], min_score: 0.5)
      assert Enum.map(ranked.ranked, & &1.bookmark.number) == [1]
      assert [%{bookmark: %{number: 2}, why: "below the line"}] = ranked.rejected
    end
  end

  describe "a turn" do
    setup do
      witness = Fixtures.account!()
      resident = Fixtures.resident!(witness)
      actor = Actor.new(:witness, witness.id)
      brain = Actor.new(:resident, resident.id, "fake/model")
      :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
      {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
      on_exit(fn -> Fake.clear(for: resident.id) end)

      at = Clock.now()

      :ok =
        Kumbukumbu.capture(
          resident.id,
          key,
          "anchor",
          at,
          [%{role: :user, content: "a moment", sent_at: at, actor: actor}],
          brain
        )

      lines = [
        {"the heron by the weir at dawn", nil},
        {"the heron flew over the weir again", nil},
        {"a correction: the heron nests upstream, not at the weir", "correction"},
        {"the kettle on the stove", nil},
        {"pinned: the day she was named", nil}
      ]

      for {{line, register}, n} <- Enum.with_index(lines, 1) do
        {:ok, ^n} =
          Kumbukumbu.add_bookmark(
            resident.id,
            %{
              session_key: key,
              anchor_ref: "anchor",
              line: line,
              summary: line,
              register: register
            },
            brain
          )
      end

      :ok = Kumbukumbu.pin_bookmark(resident.id, 5, brain)
      {:ok, id: resident.id, key: key, actor: actor, brain: brain}
    end

    defp edges(id), do: Scope.resident(id, fn -> Store.edges_from([1, 2, 3, 4, 5]) end)

    test "the pins are the prefix's and never the index's", ctx do
      test = self()

      Fake.script(
        fn %{messages: messages} ->
          send(test, {:request, messages})
          {:ok, "Yes."}
        end,
        for: ctx.id
      )

      {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "the heron at the weir", ctx.actor)
      assert_received {:request, messages}
      system = Enum.filter(messages, &(&1.role == :system))
      pins = Enum.find(system, &String.starts_with?(&1.content, "# Pinned"))
      assert pins.content =~ "#5 " and pins.content =~ "the day she was named"
      index = Enum.find(system, &(&1.content =~ "memory_feedback(used: [numbers])"))
      refute index.content =~ "the day she was named"
    end

    test "a reply with its feedback ends the turn in one call, and teaches the edges once", ctx do
      test = self()

      Fake.script(
        fn _request ->
          send(test, :asked)
          {:calls, [%{name: "memory_feedback", arguments: %{used: [1, 2]}}], "The heron, yes."}
        end,
        for: ctx.id
      )

      {:ok, %{messages: messages}} =
        Oneiroi.Brain.turn(ctx.id, ctx.key, "the heron at the weir", ctx.actor)

      assert_received :asked
      refute_received :asked
      assert [:user, :tool, :assistant] = Enum.map(messages, & &1.role)
      assert List.last(messages).content == "The heron, yes."

      by_pair = Map.new(edges(ctx.id), &{{&1.from_number, &1.to_number}, &1.w})

      # Used together: each toward the other.
      assert by_pair[{1, 2}] > 0 and by_pair[{2, 1}] > 0
      # Returned and not used, while 1 and 2 were: the step down, but
      # never against the correction (#3).
      # Every one of the four was a seed, so 1 → 4 gained the co-return
      # and lost the ignored step: no longer positive (and, near neutral,
      # under the floor and gone), while 1 → 2 holds both gains.
      refute Map.get(by_pair, {1, 4}, 0.0) > 0
      refute Map.get(by_pair, {2, 4}, 0.0) > 0
      assert by_pair[{1, 2}] > 0.15
      refute Enum.any?(by_pair, fn {{from, to}, w} -> from in [1, 2] and to == 3 and w < 0 end)
      # The pin is never ranked, so never an edge's end.
      refute Enum.any?(by_pair, fn {{from, to}, _w} -> 5 in [from, to] end)
    end

    test "a turn with no feedback learns no negative: a forgotten call demotes nothing", ctx do
      Fake.reply("Yes.", for: ctx.id)
      {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "the heron at the weir", ctx.actor)
      ws = Enum.map(edges(ctx.id), & &1.w)
      assert ws != []
      assert Enum.all?(ws, &(&1 > 0))
    end

    test "a ranked turn's recording carries the embedding model, and the export takes it along",
         ctx do
      Fake.reply("Yes.", for: ctx.id)
      {:ok, _} = Oneiroi.Brain.turn(ctx.id, ctx.key, "the heron at the weir", ctx.actor)
      dir = Path.join(System.tmp_dir!(), "oneiroi-ranked-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(dir) end)
      Clock.Fake.advance(120)
      {:ok, _} = Export.write(ctx.id, dir)

      lines =
        Path.join([dir, "records", "events", "*.jsonl"])
        |> Path.wildcard()
        |> Enum.flat_map(&(&1 |> File.read!() |> String.split("\n", trim: true)))
        |> Enum.map(&Jason.decode!/1)
        |> Enum.filter(&(&1["type"] == "Oneiroi.Kumbukumbu.Events.RetrievalRecorded"))

      model = Oneiroi.Config.fetch!(:kumbukumbu, :embedding_model)

      ranked =
        Enum.filter(lines, fn l -> Enum.any?(l["data"]["uses"], &(&1["stage"] == "seed")) end)

      assert ranked != []
      assert Enum.all?(ranked, &(&1["version"] == 2 and &1["data"]["embedding_model"] == model))
    end
  end
end
