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
    assert %Events.SeedFileWritten{file: "SOUL.md", origin: "drafted", model: "m", prompt: "p"} =
             Resident.execute(
               created(),
               write("SOUL.md", "x", origin: "drafted", model: "m", prompt: "p")
             )

    assert [] = Resident.execute(fold(created(), [write("SOUL.md", "x")]), write("SOUL.md", "x"))
    assert {:error, :file_unknown} = Resident.execute(created(), write("AGENTS.md", "x"))

    assert {:error, :origin_invalid} =
             Resident.execute(created(), write("SOUL.md", "x", origin: "found"))

    assert {:error, :content_invalid} = Resident.execute(created(), write("SOUL.md", <<0xFF>>))

    assert {:error, :content_invalid} =
             Resident.execute(created(), write("SOUL.md", String.duplicate("a", 64_001)))

    assert {:error, :write_instead} =
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
    assert {:error, :propose_instead} = Resident.execute(after_fc, write("SOUL.md", "y"))

    assert %Events.SoulEditApplied{ref: nil, file: "SOUL.md", content: "y"} =
             Resident.execute(after_fc, write("SOUL.md", "y", actor: @resident))

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

    assert [%Events.SoulEditAccepted{ref: "p1"}, %Events.SoulEditApplied{ref: "p1", content: "z"}] =
             Resident.execute(proposed, accept)

    assert %{files: %{"SOUL.md" => "z"}} = fold(proposed, [accept])
    assert {:error, :no_such_proposal} = Resident.execute(fold(proposed, [accept]), accept)

    decline = %Commands.DeclineSoulEdit{
      actor: @resident,
      at: @at,
      note: "no",
      id: "r1",
      ref: "p1"
    }

    assert %Events.SoulEditDeclined{} = Resident.execute(proposed, decline)
    assert {:error, :no_such_proposal} = Resident.execute(fold(proposed, [decline]), accept)
  end
end
