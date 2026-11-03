defmodule Oneiroi.Brain.SnowballTest do
  @moduledoc """
  The snowball of 2026-11-03: transcript_search answered whole messages,
  its own earlier answers among them, each search carried the last, and
  one grew to 2.4M characters; replayed, a turn asked the model for 1.9M
  tokens. A search now answers the words around the phrase and never a
  tool's record; a tool's answer enters a turn bounded; a past one
  replays as its head.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Cut
  alias Oneiroi.Brain.History
  alias Oneiroi.Config
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, resident: resident, key: key, actor: actor}
  end

  defp search(ctx, reply) do
    # The first round calls the tool; the round after, its answer back, replies.
    Fake.calls([%{name: "transcript_search", arguments: %{q: "astroturf"}}], reply,
      for: ctx.resident.id
    )

    {:ok, %{messages: messages}} =
      Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "look it up", ctx.actor)

    Enum.find(messages, &(&1.role == :tool)).content
  end

  test "a search answers the words around the phrase, and the next search does not find the last",
       ctx do
    padding = String.duplicate("a long paste about something else entirely. ", 2_000)
    Fake.reply("Noted.", for: ctx.resident.id)

    assert {:ok, _} =
             Oneiroi.Brain.turn(
               ctx.resident.id,
               ctx.key,
               padding <> "astroturf" <> padding,
               ctx.actor
             )

    first = search(ctx, "Found it.")

    # The second search runs as the tool does in a turn; the fake model
    # answers at once when a request already holds a tool message, and
    # the replayed transcript now does.
    turn = %{
      resident_id: ctx.resident.id,
      session_key: ctx.key,
      turn_ref: "t-again",
      started_at: Oneiroi.Apsu.Clock.now(),
      resident: Actor.new(:resident, ctx.resident.id, "fake/model")
    }

    second = Oneiroi.Brain.Tools.run("transcript_search", ~s({"q":"astroturf"}), turn)

    assert first =~ "astroturf" and String.length(first) < 1_000
    refute second =~ "transcript_search("
    assert String.length(second) < 1_000
  end

  test "a tool's answer enters a turn bounded, and a past one replays as its head" do
    limit = Config.fetch!(:brain, :tool_result_chars)
    long = String.duplicate("x", limit + 500)
    assert Cut.cut(long, limit) =~ "[cut: 500 more characters]"
    assert Cut.cut("short", limit) == "short"

    head = Config.fetch!(:brain, :history_tool_chars)
    rows = [%{role: "tool", content: "t({}) -> " <> String.duplicate("y", head * 10)}]
    [_call, %{content: replayed}] = History.messages(rows)
    assert String.length(replayed) < head + 100
    assert [%{content: words}] = History.words(rows)
    assert String.length(words) < head + 100
  end

  test "around finds the phrase whatever its case, and keeps characters whole" do
    text = String.duplicate("é", 300) <> "AstroTurf" <> String.duplicate("ü", 300)
    hit = Cut.around(text, "astroturf", 10)

    assert hit ==
             "…" <> String.duplicate("é", 10) <> "AstroTurf" <> String.duplicate("ü", 10) <> "…"

    assert String.valid?(hit)
    assert Cut.around("no such thing", "astroturf", 5) == "no such th\n[cut: 3 more characters]"
    assert Cut.around("anything", "  ", 5) =~ "anything"
  end
end
