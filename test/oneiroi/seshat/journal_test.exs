defmodule Oneiroi.Seshat.JournalTest do
  @moduledoc "The journal through the exports and the brain: rows numbered within their day, the day row opened by the schedule on the journal's ask, the rendered file registered and indexed with its citations, todos, the delta, the section and the tools."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seshat
  alias Oneiroi.Sunna

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    Model.clear()
    Honcho.clear(for: resident.id)

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
      File.rm_rf!(dir)
    end)

    {:ok, id: resident.id, slug: resident.slug, actor: actor, brain: brain, key: key, dir: dir}
  end

  test "rows are numbered within their day, the day row is opened on the journal's ask, and the file is rendered, registered and indexed with its citations",
       ctx do
    id = ctx.id
    assert [] = Sunna.days(id, 10)
    assert "" == Seshat.journal_text(id)

    {:ok, 1} =
      Sunna.set_date(
        id,
        nil,
        %{title: "the fair", on: ~U[2026-11-05 14:00:00Z], kind: "deadline"},
        ctx.actor
      )

    assert {:ok, %{day: "2026-10-26", number: 1, kind: "plan"}} =
             Seshat.journal_add(
               id,
               nil,
               "plan",
               "Bake for the fair (#{ctx.slug}:date/1).",
               ctx.brain
             )

    assert {:ok, %{number: 2}} =
             Seshat.journal_add(id, "2026-10-26", "todo", "Buy flour", ctx.brain)

    assert {:ok, %{number: 3}} =
             Seshat.journal_add(id, "2026-10-26", "note", "The oven runs hot.", ctx.actor)

    assert {:ok, %{day: "2026-10-25", number: 1}} =
             Seshat.journal_add(id, "2026-10-25", "plan", "Rest.", ctx.brain)

    assert [%{day: "2026-10-26"}, %{day: "2026-10-25"}] = Sunna.days(id, 10)

    # One DayOpened per day on the stream, whatever the row's idempotent
    # insert would forgive: the probe that dropped the aggregate's guard
    # printed ok until this read. And the schedule's own day check,
    # which the journal's edge translates, is reachable on its own.
    {:ok, events} = Oneiroi.EventStore.read_stream_forward("schedule-" <> id, 0, 100)
    assert Enum.count(events, &match?(%{data: %Sunna.Events.DayOpened{}}, &1)) == 2

    assert {:error, %Sunna.Error{kind: :sunna_day_invalid}} =
             Sunna.open_day(id, "yesterday", ctx.actor)

    # The rendered narrative follows the rows; it is a registered, indexed document of the journal kind.
    rendered = File.read!(Path.join(ctx.dir, "journal/2026-10-26.md"))

    assert rendered ==
             "# 2026-10-26\n\n## Plan\n\n- (1) Bake for the fair (#{ctx.slug}:date/1).\n\n## Notes\n\n- (3) The oven runs hot.\n\n## To do\n\n- [ ] (2) Buy flour\n"

    assert %{kind: "journal", origin: "written", chunks: 1, title: "2026-10-26"} =
             Enum.find(Seshat.documents(id), &(&1.path == "journal/2026-10-26.md"))

    assert [%{target: target, resolved: true, label: "the fair"}] =
             Seshat.references(id, "journal/2026-10-26.md")

    assert target == "#{ctx.slug}:date/1"

    # The day is citeable from a piece, and the journal kind is not writable through a document write.
    assert {:ok, _} =
             Seshat.write(
               id,
               "writing/fair.md",
               "See #{ctx.slug}:journal/2026-10-26 and #{ctx.slug}:journal/2026-10-26#2.",
               ctx.brain
             )

    assert [%{resolved: true, label: "2026-10-26"}, %{resolved: true}] =
             Seshat.references(id, "writing/fair.md")

    assert {:error, %Seshat.Error{kind: :seshat_kind_not_writable}} =
             Seshat.write(id, "journal/2026-10-26.md", "x", ctx.brain)

    # A to-do is done once and re-rendered; a number that is no to-do is named.
    assert :ok = Seshat.journal_done(id, "2026-10-26", 2, ctx.brain)
    assert :ok = Seshat.journal_done(id, "2026-10-26", 2, ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_no_such_todo}} =
             Seshat.journal_done(id, "2026-10-26", 3, ctx.brain)

    assert File.read!(Path.join(ctx.dir, "journal/2026-10-26.md")) =~ "- [x] (2) Buy flour"

    assert %{
             opened_at: %DateTime{},
             entries: [
               %{number: 1, kind: "plan", actor_kind: "resident"},
               %{number: 2, done_at: %DateTime{}},
               %{number: 3, actor_kind: "witness"}
             ],
             delta: %{plan: 1, todo: 1, done: 1, note: 1, wrap: 0, unwrapped: true}
           } =
             Seshat.journal_day(id, "2026-10-26")

    assert nil == Seshat.journal_day(id, "2026-10-01")

    assert [
             %{day: "2026-10-26", delta: %{plan: 1, done: 1, unwrapped: true}},
             %{day: "2026-10-25", delta: %{plan: 1, unwrapped: true}}
           ] = Seshat.journal_days(id, 10)

    # Today is planned and not yet wrapped, and still not counted: the
    # day is not over (the probe that stopped excluding it printed ok
    # while today was already wrapped).
    assert ["2026-10-25"] = Seshat.unwrapped_days(id, 7)

    assert {:ok, %{number: 4, kind: "wrap"}} =
             Seshat.journal_add(id, nil, "wrap", "Baked two loaves.", ctx.brain)

    assert %{delta: %{wrap: 1, unwrapped: false}} = Seshat.journal_day(id, "2026-10-26")
    assert Seshat.journal_text(id) =~ "## Wrap\n\n- (4) Baked two loaves."

    # Yesterday was planned and never wrapped; today is not counted whatever its state.
    assert ["2026-10-25"] = Seshat.unwrapped_days(id, 7)

    assert {:error, %Seshat.Error{kind: :seshat_entry_kind_invalid}} =
             Seshat.journal_add(id, nil, "poem", "x", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_entry_text_invalid}} =
             Seshat.journal_add(id, nil, "note", "  ", ctx.brain)

    assert {:error, %Seshat.Error{kind: :seshat_day_invalid}} =
             Seshat.journal_add(id, "yesterday", "note", "x", ctx.brain)
  end

  test "the day the schedule opened at a check-in is the journal's day, and the brain writes and reads through its tools with today's rows as a section",
       ctx do
    id = ctx.id
    {:ok, _} = Sunna.set_checkin(id, nil, "morning", "12:01", ctx.actor)
    Clock.Fake.advance(120)
    Model.reply("Good morning.", for: id)
    :ok = Sunna.tick(id)
    assert [%{day: "2026-10-26"}] = Sunna.days(id, 10)
    assert %{entries: []} = Seshat.journal_day(id, "2026-10-26")

    test = self()

    Model.calls(
      [
        %{name: "journal_add", arguments: %{kind: "plan", text: "Write the bake-off piece."}},
        %{name: "journal_add", arguments: %{kind: "todo", text: "Proof the dough"}},
        %{name: "journal_read", arguments: %{day: "2026-10-26"}}
      ],
      "Planned.",
      for: id
    )

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "what's the plan?", ctx.actor)

    tools = for %{role: :tool, content: c} <- messages, do: c
    # Three calls, not four: a fourth would carry the session over the
    # suite's compaction threshold (BRAIN_COMPACT_AFTER_MESSAGES) and the
    # next turn's first call would be the memory flush, not the turn.
    assert String.ends_with?(Enum.at(tools, 0), "-> Added plan 1 to 2026-10-26.")
    assert Enum.at(tools, 2) =~ "- [ ] (2) Proof the dough"

    assert Enum.at(tools, 2) =~
             "Delta: 1 planned, 0 of 1 todos done, 0 wrap (planned and not wrapped)."

    Model.script(
      fn %{messages: shown} ->
        send(test, {:shown, shown})
        {:ok, "Yes."}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "and?", ctx.actor)
    assert_received {:shown, shown}

    assert Enum.any?(
             shown,
             &(&1.role == :system and &1.content =~ "## Plan\n\n- (1) Write the bake-off piece.")
           )

    assert Enum.any?(Kumbukumbu.injections({:resident, id}, ref), &(&1.label == "journal"))
  end
end
