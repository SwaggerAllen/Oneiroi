defmodule Oneiroi.AgathosDaimon.IdentityTest do
  @moduledoc "The aggregate on its files, pure: seeds before first contact, proposals after, first contact once."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Resident

  @at ~U[2026-10-26 12:00:00Z]
  @witness Actor.new(:witness, "a1")
  @resident Actor.new(:resident, "r1", "fake/model")

  defp created do
    Resident.apply(%Resident{}, %Events.ResidentCreated{
      actor: @witness,
      at: @at,
      id: "r1",
      name: "Lily",
      slug: "lily",
      witness_account_id: "a1"
    })
  end

  defp fold(state, commands) do
    Enum.reduce(commands, state, fn c, r ->
      r |> Resident.execute(c) |> List.wrap() |> Enum.reduce(r, &Resident.apply(&2, &1))
    end)
  end

  defp write(file, content, extra \\ []) do
    struct!(
      Commands.WriteFile,
      Keyword.merge(
        [actor: @witness, at: @at, id: "r1", file: file, content: content, origin: "authored"],
        extra
      )
    )
  end

  defp first_contact,
    do: %Commands.RecordFirstContact{
      actor: @resident,
      at: @at,
      id: "r1",
      session_key: "s",
      turn_ref: "t"
    }

  test "a seed is written with its origin, once per content, only for a known file" do
    assert [
             %Events.SeedFileWritten{file: "SOUL.md", origin: "drafted", model: "m", prompt: "p"},
             %Events.IdMinted{kind: "soul", number: 1},
             %Events.SoulLineWritten{number: 1, text: "x", cites: []},
             %Events.SoulLinesOrdered{numbers: [1]}
           ] =
             Resident.execute(
               created(),
               write("SOUL.md", "x", origin: "drafted", model: "m", prompt: "p")
             )

    assert [] = Resident.execute(fold(created(), [write("SOUL.md", "x")]), write("SOUL.md", "x"))

    assert {:error,
            %{
              kind: :agathos_daimon_file_unknown,
              site: :agathos_daimon_resident_write_file_unknown,
              details: [file: "AGENTS.md", files: _]
            }} = Resident.execute(created(), write("AGENTS.md", "x"))

    assert {:error,
            %{
              kind: :agathos_daimon_origin_invalid,
              site: :agathos_daimon_resident_write_file_origin_invalid
            }} =
             Resident.execute(created(), write("SOUL.md", "x", origin: "found"))

    assert {:error,
            %{
              kind: :agathos_daimon_content_invalid,
              site: :agathos_daimon_resident_write_file_content_invalid
            }} = Resident.execute(created(), write("SOUL.md", <<0xFF>>))

    assert {:error,
            %{
              kind: :agathos_daimon_content_invalid,
              site: :agathos_daimon_resident_write_file_content_invalid
            }} =
             Resident.execute(created(), write("SOUL.md", String.duplicate("a", 64_001)))

    assert {:error,
            %{
              kind: :agathos_daimon_write_instead,
              site: :agathos_daimon_resident_propose_edit_write_instead
            }} =
             Resident.execute(created(), %Commands.ProposeSoulEdit{
               actor: @witness,
               at: @at,
               note: "n",
               id: "r1",
               ref: "p1",
               file: "SOUL.md",
               content: "y"
             })
  end

  test "first contact is recorded once and flips a witness's write to a proposal" do
    assert %Events.FirstContact{session_key: "s", turn_ref: "t"} =
             Resident.execute(created(), first_contact())

    after_fc = fold(created(), [write("SOUL.md", "x"), first_contact()])
    assert [] = Resident.execute(after_fc, first_contact())

    assert {:error,
            %{
              kind: :agathos_daimon_propose_instead,
              site: :agathos_daimon_resident_write_file_propose_instead
            }} = Resident.execute(after_fc, write("SOUL.md", "y"))

    assert [
             %Events.SoulEditApplied{ref: nil, file: "SOUL.md", content: "y"},
             %Events.SoulLineReworded{number: 1, text: "y"}
           ] = Resident.execute(after_fc, write("SOUL.md", "y", actor: @resident))

    propose = %Commands.ProposeSoulEdit{
      actor: @witness,
      at: @at,
      note: "you have grown",
      id: "r1",
      ref: "p1",
      file: "SOUL.md",
      content: "z"
    }

    assert %Events.SoulEditProposed{ref: "p1"} = Resident.execute(after_fc, propose)
    proposed = fold(after_fc, [propose])
    assert [] = Resident.execute(proposed, propose)

    accept = %Commands.AcceptSoulEdit{actor: @resident, at: @at, note: "yes", id: "r1", ref: "p1"}

    assert [
             %Events.SoulEditAccepted{ref: "p1"},
             %Events.SoulEditApplied{ref: "p1", content: "z"},
             %Events.SoulLineReworded{number: 1, text: "z", cites: []}
           ] = Resident.execute(proposed, accept)

    assert %{files: %{"SOUL.md" => "z"}} = fold(proposed, [accept])

    assert {:error,
            %{
              kind: :agathos_daimon_no_such_proposal,
              site: :agathos_daimon_resident_accept_edit_no_such_proposal
            }} = Resident.execute(fold(proposed, [accept]), accept)

    decline = %Commands.DeclineSoulEdit{
      actor: @resident,
      at: @at,
      note: "no",
      id: "r1",
      ref: "p1"
    }

    assert %Events.SoulEditDeclined{} = Resident.execute(proposed, decline)

    assert {:error,
            %{
              kind: :agathos_daimon_no_such_proposal,
              site: :agathos_daimon_resident_accept_edit_no_such_proposal
            }} = Resident.execute(fold(proposed, [decline]), accept)
  end

  test "the soul file is lines: minted in order, reworded under their numbers, retired when dropped, the markers stripped from the words" do
    alias Oneiroi.AgathosDaimon.SoulLines

    first = write("SOUL.md", "# Soul\n\nA.\n\nB.\n\nC.")

    assert [
             %Events.SeedFileWritten{content: "# Soul\n\nA.\n\nB.\n\nC."},
             %Events.IdMinted{kind: "soul", number: 1},
             %Events.SoulLineWritten{number: 1, text: "A."},
             %Events.IdMinted{kind: "soul", number: 2},
             %Events.SoulLineWritten{number: 2, text: "B."},
             %Events.IdMinted{kind: "soul", number: 3},
             %Events.SoulLineWritten{number: 3, text: "C."},
             %Events.SoulLinesOrdered{numbers: [1, 2, 3]}
           ] = Resident.execute(created(), first)

    r = fold(created(), [first])
    assert %{soul: [{1, "A."}, {2, "B."}, {3, "C."}], sequences: %{"soul" => 3}} = r

    # The rendered file written back is no event: the markers are not words.
    rendered =
      SoulLines.render(r.files["SOUL.md"], [
        %{number: 1, text: "A."},
        %{number: 2, text: "B."},
        %{number: 3, text: "C."}
      ])

    assert rendered == "# Soul\n\n[soul/1] A.\n\n[soul/2] B.\n\n[soul/3] C."
    assert [] = Resident.execute(r, write("SOUL.md", rendered))

    # A kept line keeps its number wherever it moves; a marker is the
    # claim, so the reworded line keeps its number and the unmarked
    # paragraph is new; the dropped line retires; the stored content is
    # the words alone; a heading alone is the file's event and nothing
    # of the lines.
    second = write("SOUL.md", "# Soul\n\n[soul/2] B.\n\n[soul/1] A, reworded.\n\nD.", cites: [4])

    assert [
             %Events.SeedFileWritten{content: "# Soul\n\nB.\n\nA, reworded.\n\nD."},
             %Events.SoulLineReworded{number: 1, text: "A, reworded.", cites: [4]},
             %Events.IdMinted{kind: "soul", number: 4},
             %Events.SoulLineWritten{number: 4, text: "D.", cites: [4]},
             %Events.SoulLineRetired{number: 3},
             %Events.SoulLinesOrdered{numbers: [2, 1, 4]}
           ] = Resident.execute(r, second)

    r2 = fold(r, [second])
    assert %{soul: [{2, "B."}, {1, "A, reworded."}, {4, "D."}]} = r2

    # With no markers at all the new paragraphs pair with the old lines
    # in order: a seed or a hand edit rewording a line is still that line.
    assert [
             %Events.SeedFileWritten{},
             %Events.SoulLineReworded{number: 1, text: "A!"},
             %Events.SoulLineReworded{number: 3, text: "C!"}
           ] = Resident.execute(r, write("SOUL.md", "# Soul\n\nA!\n\nB.\n\nC!"))

    assert [%Events.SeedFileWritten{}] =
             Resident.execute(r2, write("SOUL.md", "# My soul\n\nB.\n\nA, reworded.\n\nD."))

    # Dropped lines retire and a new paragraph beyond them mints the next number.
    third = write("SOUL.md", "# Soul\n\nB.")

    assert [
             %Events.SeedFileWritten{},
             %Events.SoulLineRetired{number: 1},
             %Events.SoulLineRetired{number: 4},
             %Events.SoulLinesOrdered{numbers: [2]}
           ] = Resident.execute(r2, third)

    r3 = fold(r2, [third])
    assert %{soul: [{2, "B."}]} = r3

    # A marker naming a retired or unminted number is no claim: the line is new.
    assert [
             %Events.SeedFileWritten{},
             %Events.IdMinted{kind: "soul", number: 5},
             %Events.SoulLineWritten{number: 5, text: "E.", cites: []},
             %Events.SoulLinesOrdered{numbers: [2, 5]}
           ] = Resident.execute(r3, write("SOUL.md", "# Soul\n\nB.\n\n[soul/9] E."))

    assert {:error,
            %{
              kind: :agathos_daimon_cites_invalid,
              site: :agathos_daimon_resident_write_file_cites_invalid
            }} = Resident.execute(r3, write("SOUL.md", "E.", cites: [0]))

    assert {:error,
            %{
              kind: :agathos_daimon_cites_invalid,
              site: :agathos_daimon_resident_write_file_cites_invalid
            }} = Resident.execute(r3, write("SOUL.md", "E.", cites: "4"))

    # Any other file has no lines.
    assert [%Events.SeedFileWritten{file: "USER.md"}] =
             Resident.execute(r3, write("USER.md", "# You\n\nA gardener."))
  end
end
