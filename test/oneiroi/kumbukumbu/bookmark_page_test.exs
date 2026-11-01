defmodule Oneiroi.Kumbukumbu.BookmarkPageTest do
  @moduledoc """
  Paging back past the index (kumbukumbu #39) and what the index holds
  now (kumbukumbu #38): newest first under the page bound, each filter
  alone and combined, the pins alone, the room's line held, and the
  Memory screen's index read from the build, not from a turn's marks.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    id = resident.id
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, actor)

    {:ok, ikey} =
      Kumbukumbu.open_session(id, "free_time", "brain", [witness.id], actor, domain: "intimate")

    at = Clock.now()

    for {k, ref} <- [{key, "t-main"}, {ikey, "t-intimate"}] do
      :ok =
        Kumbukumbu.capture(
          id,
          k,
          ref,
          at,
          [%{role: :assistant, content: "a moment", sent_at: at, actor: brain}],
          brain
        )
    end

    {:ok, id: id, actor: actor, brain: brain, key: key, ikey: ikey, at: at}
  end

  defp add(ctx, n, opts \\ []) do
    {key, ref} =
      if opts[:intimate], do: {ctx.ikey, "t-intimate"}, else: {ctx.key, "t-main"}

    attrs = %{
      session_key: key,
      anchor_ref: ref,
      line: Keyword.get(opts, :line, "moment #{n}"),
      anchor_at: Keyword.get(opts, :at, ctx.at)
    }

    {:ok, ^n} = Kumbukumbu.add_bookmark(ctx.id, attrs, ctx.brain)
    if opts[:pinned], do: :ok = Kumbukumbu.pin_bookmark(ctx.id, n, ctx.actor)
    n
  end

  defp numbers(%{rows: rows}), do: Enum.map(rows, & &1.number)

  test "pages newest first under the bound and says how many lie further back", ctx do
    size = Config.fetch!(:kumbukumbu, :page_bookmarks)
    total = size + 5
    for n <- 1..total, do: add(ctx, n)

    first = Kumbukumbu.bookmark_page(ctx.id, ctx.key, [])
    assert numbers(first) == Enum.to_list(total..(total - size + 1)//-1)
    assert first.further == 5

    last = Kumbukumbu.bookmark_page(ctx.id, ctx.key, before: List.last(first.rows).number)
    assert numbers(last) == [5, 4, 3, 2, 1]
    assert last.further == 0
  end

  test "each filter narrows, and they combine", ctx do
    :ok = Kumbukumbu.create_tag(ctx.id, "haven", ctx.actor)
    add(ctx, 1, line: "the heron at dawn", at: ~U[2026-10-01 08:00:00.000000Z])
    add(ctx, 2, line: "the kettle", at: ~U[2026-10-10 08:00:00.000000Z], pinned: true)
    add(ctx, 3, line: "the Heron again", at: ~U[2026-10-20 08:00:00.000000Z], pinned: true)
    add(ctx, 4, line: "the heron, later", at: ~U[2026-10-21 08:00:00.000000Z])
    :ok = Kumbukumbu.apply_tag(ctx.id, "haven", "bookmark", "3", ctx.actor)
    :ok = Kumbukumbu.apply_tag(ctx.id, "haven", "bookmark", "4", ctx.actor)

    page = &numbers(Kumbukumbu.bookmark_page(ctx.id, ctx.key, &1))

    assert page.(text: "HERON") == [4, 3, 1]
    assert page.(tag: "haven") == [4, 3]
    assert page.(pinned: true) == [3, 2]
    assert page.(from: ~D[2026-10-10], to: ~D[2026-10-20]) == [3, 2]
    assert page.(before: 3) == [2, 1]
    assert page.(pinned: true, tag: "haven") == [3]
    assert page.(pinned: true, text: "kettle") == [2]
    assert page.(pinned: true, text: "heron", tag: "haven") == [3]
    assert page.(pinned: false) == [4, 3, 2, 1]
  end

  test "the pins page alone, every one, past what the pins' half of the index could hold",
       ctx do
    size = Config.fetch!(:kumbukumbu, :page_bookmarks)
    # About 33 tokens a line: the pins' half of the budget holds fewer
    # than these.
    long = String.duplicate("a pinned moment worth keeping ", 3) <> "and more words"
    pins = size + 8
    for n <- 1..pins, do: add(ctx, n, line: "#{n} " <> long, pinned: true)
    add(ctx, pins + 1, line: "not pinned")

    index = Kumbukumbu.index(ctx.id, ctx.key)
    left = Enum.reject(1..pins, &(&1 in index.included))
    assert left != []

    assert index.text =~
             "#{length(left)} pins not shown; bookmark_list(pinned: true) lists every pin."

    first = Kumbukumbu.bookmark_page(ctx.id, ctx.key, pinned: true)
    assert numbers(first) == Enum.to_list(pins..(pins - size + 1)//-1)
    assert first.further == 8

    rest =
      Kumbukumbu.bookmark_page(ctx.id, ctx.key,
        pinned: true,
        before: List.last(first.rows).number
      )

    assert numbers(rest) == Enum.to_list(8..1//-1)
    assert Enum.all?(left, &(&1 in (numbers(first) ++ numbers(rest))))
  end

  test "the room's line holds: a bookmark of another domain is never listed outside it", ctx do
    add(ctx, 1)
    add(ctx, 2, intimate: true, pinned: true)
    add(ctx, 3)

    assert numbers(Kumbukumbu.bookmark_page(ctx.id, ctx.key, [])) == [3, 1]
    assert numbers(Kumbukumbu.bookmark_page(ctx.id, ctx.key, pinned: true)) == []
    assert numbers(Kumbukumbu.bookmark_page(ctx.id, ctx.ikey, [])) == [3, 2, 1]
    assert numbers(Kumbukumbu.bookmark_page(ctx.id, ctx.ikey, pinned: true)) == [2]
  end

  test "what the index holds now is the build, with no turn ever taken", ctx do
    add(ctx, 1, pinned: true)
    add(ctx, 2)
    add(ctx, 3, intimate: true)

    # Nothing has marked a bookmark: no turn has run.
    assert Enum.all?(Kumbukumbu.bookmarks(ctx.id), &is_nil(&1.last_indexed_at))

    budget = Config.fetch!(:kumbukumbu, :index_tokens)

    assert %{listed: [1, 2], left_out: 0, elsewhere: 1, budget: ^budget, description: text} =
             Kumbukumbu.index_now(ctx.id)

    assert text =~ "2 bookmarks listed under a budget of #{budget} tokens (a bound)"
    assert text =~ "1 bookmark made in a named room is listed only in that room's conversations."
    refute text =~ "left out"
  end
end
