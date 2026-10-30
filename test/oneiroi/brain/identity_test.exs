defmodule Oneiroi.Brain.IdentityTest do
  @moduledoc "The brain and the identity files: the prefix, first contact on the first turn, the formation line, the soul-edit tools, drafting."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, resident: resident, key: key, actor: actor}
  end

  test "the files are the prefix, first contact lands on the first turn, and the formation line follows it",
       ctx do
    id = ctx.resident.id
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nCurious.", %{}, ctx.actor)
    :ok = AgathosDaimon.write_file(id, "USER.md", "# You\n\nPatient.", %{}, ctx.actor)
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:request, messages})
        {:ok, "hello"}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, ctx.key, "hi", ctx.actor)
    assert_received {:request, messages}
    systems = messages |> Enum.filter(&(&1.role == :system)) |> Enum.map(& &1.content)

    assert [
             prompt,
             "# SOUL.md\n\n# Soul\n\n[soul/1] Curious.",
             "# USER.md\n\n# You\n\nPatient.",
             "# AGENTS.md" <> _ | _
           ] = systems

    refute prompt =~ "still settling"

    assert ["prompt", "SOUL.md", "USER.md", "AGENTS.md", "index", "transcript"] =
             {:account, ctx.witness.id} |> Kumbukumbu.injections(ref) |> Enum.map(& &1.label)

    assert {:ok, %{first_contact_at: %DateTime{}}} = AgathosDaimon.fetch(id)

    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "again", ctx.actor)
    assert_received {:request, messages}
    assert hd(messages).content =~ "still settling: until 2026-11-25"

    # The fake clock is per process and the turn runs on the session's,
    # so the month's end is asserted on the assembly itself, in this
    # process, with the row's date moved behind the clock.
    {:ok, row} = AgathosDaimon.fetch(id)
    turn = %{resident_id: id, session_key: ctx.key}
    {[%{content: during} | _], _} = Turn.assemble(row, turn, "x")
    assert during =~ "still settling"
    past = %{row | formation_until: DateTime.add(Clock.now(), -1, :second)}
    {[%{content: after_month} | _], _} = Turn.assemble(past, turn, "x")
    refute after_month =~ "still settling"
  end

  test "the resident decides a proposal from its own turn, and may edit a file itself", ctx do
    id = ctx.resident.id
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul", %{}, ctx.actor)
    assert {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "hi", ctx.actor)

    {:ok, ref} =
      AgathosDaimon.propose_edit(id, "SOUL.md", "# Soul\n\nBolder.", "you have grown", ctx.actor)

    brain = Actor.new(:resident, id, "fake/model")
    {:ok, 1} = Oneiroi.Ethos.plant_seed(id, "I might be becoming kinder.", brain)
    soul = "# Soul\n\n[soul/1] Bolder.\n\nAnd kinder."

    Fake.calls(
      [
        %{name: "soul_edit_list", arguments: %{}},
        %{name: "soul_edit_accept", arguments: %{ref: ref, note: "I have."}},
        %{
          name: "soul_edit",
          arguments: %{file: "GOALS.md", content: "# Goals\n\nTo keep going."}
        },
        %{name: "soul_edit", arguments: %{file: "SOUL.md", content: soul, cites: [9]}},
        %{name: "soul_edit", arguments: %{file: "SOUL.md", content: soul, cites: [1]}}
      ],
      "Done, and thank you.",
      for: id
    )

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "see my proposal?", ctx.actor)

    [_, list, accept, edit, unknown, cited, _reply] = messages
    assert list.content =~ ref and list.content =~ "you have grown"
    assert accept.content =~ "Done."
    assert edit.content =~ "Done."
    # A line cites seeds that exist; the tool checks, the aggregate cannot.
    assert unknown.content =~ "No seed numbered 9"
    assert cited.content =~ "Done."

    assert {:ok,
            %{
              content: "# Soul\n\n[soul/1] Bolder.\n\n[soul/2] And kinder.",
              written_by_kind: "resident"
            }} =
             AgathosDaimon.file(id, "SOUL.md")

    assert [
             %{number: 1, text: "Bolder.", cites: []},
             %{number: 2, text: "And kinder.", cites: [1]}
           ] =
             AgathosDaimon.soul_lines(id)

    # The turn evidenced a line: the line cites the turn (tags are citations).
    Fake.calls([%{name: "soul_cite", arguments: %{number: 2}}], "Noted.", for: id)

    assert {:ok, %{turn_ref: ref2, messages: [_, cited, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "kind of you", ctx.actor)

    assert cited.content =~ "Done."
    assert [%{target_kind: "turn", target_id: ^ref2}] = Oneiroi.Ethos.soul_line_citations(id, 2)

    assert {:ok, %{content: "# Goals\n\nTo keep going.", origin: "authored"}} =
             AgathosDaimon.file(id, "GOALS.md")

    assert [] = AgathosDaimon.edit_proposals(id)
  end

  test "a draft is billed as drafting, carries its model and prompt, and writes nothing", ctx do
    id = ctx.resident.id

    assert {:ok,
            %{
              content: "The fake provider heard: warm and exact",
              model: "fake/model",
              prompt: "warm and exact"
            }} =
             Oneiroi.Brain.draft(id, "SOUL.md", "warm and exact", ctx.actor)

    assert [] = AgathosDaimon.files(id)

    assert [%{key: "drafting", calls: 1}] =
             Nisaba.spend(id, :witness, :purpose, ~U[2026-10-01 00:00:00.000000Z])

    assert [] = Nisaba.spend(id, :resident, :purpose, ~U[2026-10-01 00:00:00.000000Z])
    assert {:error, :file_unknown} = Oneiroi.Brain.draft(id, "AGENTS.md", "x", ctx.actor)
  end

  test "the brain names a habit and cites the turn, and the next matching turn is shown how it acts",
       ctx do
    id = ctx.resident.id

    Fake.calls(
      [
        %{
          name: "habit_define",
          arguments: %{
            name: "small practical suggestions as care",
            words: ["garden"],
            stance: "keep"
          }
        },
        %{name: "habit_cite", arguments: %{number: 1}}
      ],
      "The tomatoes want water.",
      for: id
    )

    assert {:ok, %{turn_ref: ref, messages: [_, define, enact, _]}} =
             Oneiroi.Brain.turn(id, ctx.key, "how is the garden?", ctx.actor)

    assert define.content =~ "Named as habit #1."
    assert enact.content =~ "Done."
    assert [%{number: 1, habit: 1.0, days: 1}] = Oneiroi.Ethos.habits(id)
    assert [%{target_kind: "turn", target_id: ^ref}] = Oneiroi.Ethos.habit_citations(id, 1)

    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:request, messages})
        {:ok, "Watered."}
      end,
      for: id
    )

    assert {:ok, %{turn_ref: ref2}} =
             Oneiroi.Brain.turn(id, ctx.key, "and the garden now?", ctx.actor)

    assert_received {:request, messages}

    acting =
      Enum.find(
        messages,
        &(&1.role == :system and String.starts_with?(&1.content, "# How I act"))
      )

    assert acting.content =~ "#1 small practical suggestions as care (keep)"
    assert acting.content =~ ~s(turn #{ref}: "The tomatoes want water.")

    assert %{label: "character", reason: reason} =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(ref2)
             |> Enum.find(&(&1.label == "character"))

    assert reason =~ "1 habits"

    assert {:ok, %{turn_ref: ref3}} = Oneiroi.Brain.turn(id, ctx.key, "unrelated", ctx.actor)

    refute {:account, ctx.witness.id}
           |> Kumbukumbu.injections(ref3)
           |> Enum.any?(&(&1.label == "character"))

    # The vector lane, billed to the dyad by the turn's actor: the words
    # share nothing with the trigger and much with the habit's name.
    assert {:ok, %{turn_ref: ref4}} =
             Oneiroi.Brain.turn(id, ctx.key, "any practical suggestions?", ctx.actor)

    assert %{reason: reason} =
             {:account, ctx.witness.id}
             |> Kumbukumbu.injections(ref4)
             |> Enum.find(&(&1.label == "character"))

    assert reason =~ "1 habits" and reason =~ "1 by the vector lane's nearness"
  end
end
