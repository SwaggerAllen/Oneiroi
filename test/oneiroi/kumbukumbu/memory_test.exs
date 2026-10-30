defmodule Oneiroi.Kumbukumbu.MemoryTest do
  @moduledoc "The memory aggregate, pure: numbers once, spans that only grow, a closed tag set, taggings as a set."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Kumbukumbu.Events.Memory, as: Events
  alias Oneiroi.Kumbukumbu.Memory
  alias Oneiroi.Kumbukumbu.MemoryCommands, as: Commands

  @at ~U[2026-10-29 12:00:00.000000Z]
  @resident Actor.new(:resident, "r1", "fake/model")
  @witness Actor.new(:witness, "a1")

  defp add(number, extra \\ []) do
    struct!(
      Commands.AddBookmark,
      Keyword.merge(
        [
          actor: @resident,
          at: @at,
          id: "r1",
          number: number,
          session_key: "s1",
          anchor_ref: "t1",
          anchor_at: @at,
          turns_back: 1,
          line: "the first time she said it back",
          summary: "a longer note"
        ],
        extra
      )
    )
  end

  defp fold(commands) do
    Enum.reduce(commands, %Memory{}, fn c, m ->
      m |> Memory.execute(c) |> List.wrap() |> Enum.reduce(m, &Memory.apply(&2, &1))
    end)
  end

  test "a bookmark is added once per number; a blank or long line is refused" do
    assert %Events.BookmarkAdded{number: 1, turns_back: 1} = Memory.execute(%Memory{}, add(1))
    assert [] = Memory.execute(fold([add(1)]), add(1))
    assert {:error, :line_invalid} = Memory.execute(%Memory{}, add(2, line: "   "))

    assert {:error, :line_invalid} =
             Memory.execute(%Memory{}, add(2, line: String.duplicate("x", 121)))

    assert {:error, :span_invalid} = Memory.execute(%Memory{}, add(2, turns_back: 0))
  end

  test "a span only grows, and a pin is a decision made once" do
    m = fold([add(1)])

    extend = %Commands.ExtendBookmark{
      actor: @resident,
      at: @at,
      id: "r1",
      number: 1,
      turns_back: 3
    }

    assert %Events.BookmarkExtended{turns_back: 3} = Memory.execute(m, extend)
    m = fold([add(1), extend])
    assert {:error, :span_not_grown} = Memory.execute(m, %{extend | turns_back: 2})
    assert {:error, :no_such_bookmark} = Memory.execute(m, %{extend | number: 9})

    pin = %Commands.PinBookmark{actor: @witness, at: @at, id: "r1", number: 1}
    assert %Events.BookmarkPinned{number: 1, actor: @witness} = Memory.execute(m, pin)
    assert [] = Memory.execute(fold([add(1), pin]), pin)

    unpin = %Commands.UnpinBookmark{actor: @witness, at: @at, id: "r1", number: 1}
    assert [] = Memory.execute(m, unpin)
    assert %Events.BookmarkUnpinned{} = Memory.execute(fold([add(1), pin]), unpin)
  end

  test "a proposal is accepted by a bookmark that names it, and records who proposed" do
    propose = %Commands.ProposeBookmark{
      actor: @witness,
      at: @at,
      note: "you lit up here",
      id: "r1",
      ref: "p1",
      session_key: "s1",
      anchor_ref: "t1",
      line: "a suggested line"
    }

    assert %Events.BookmarkProposed{ref: "p1"} = Memory.execute(%Memory{}, propose)
    m = fold([propose])

    assert %Events.BookmarkAdded{proposal_ref: "p1", proposed_by: %{kind: "witness", id: "a1"}} =
             Memory.execute(m, add(1, proposal_ref: "p1"))

    assert {:error, :no_such_proposal} = Memory.execute(m, add(1, proposal_ref: "nope"))
    accepted = fold([propose, add(1, proposal_ref: "p1")])
    assert {:error, :no_such_proposal} = Memory.execute(accepted, add(2, proposal_ref: "p1"))

    decline = %Commands.DeclineBookmarkProposal{
      actor: @resident,
      at: @at,
      note: "no",
      id: "r1",
      ref: "p1"
    }

    assert %Events.BookmarkProposalDeclined{} = Memory.execute(m, decline)
    assert {:error, :no_such_proposal} = Memory.execute(accepted, decline)
  end

  test "the tag set is closed: proposed, approved or created, retired; slugs only" do
    propose = %Commands.ProposeTag{
      actor: @resident,
      at: @at,
      note: "why",
      id: "r1",
      slug: "haven"
    }

    assert %Events.TagProposed{slug: "haven"} = Memory.execute(%Memory{}, propose)
    assert {:error, :slug_invalid} = Memory.execute(%Memory{}, %{propose | slug: "Not A Slug"})
    proposed = fold([propose])
    assert [] = Memory.execute(proposed, propose)

    approve = %Commands.ApproveTag{actor: @witness, at: @at, note: "yes", id: "r1", slug: "haven"}
    assert {:error, :no_such_proposal} = Memory.execute(%Memory{}, approve)
    assert %Events.TagApproved{} = Memory.execute(proposed, approve)
    active = fold([propose, approve])
    assert {:error, :tag_exists} = Memory.execute(active, propose)

    create = %Commands.CreateTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
    assert [] = Memory.execute(active, create)
    assert {:error, :tag_proposed} = Memory.execute(proposed, create)
    assert %Events.TagCreated{} = Memory.execute(%Memory{}, create)

    retire = %Commands.RetireTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
    assert %Events.TagRetired{} = Memory.execute(active, retire)
    assert {:error, :no_such_tag} = Memory.execute(proposed, retire)

    reject = %Commands.RejectTag{actor: @witness, at: @at, note: "no", id: "r1", slug: "haven"}
    assert %Events.TagRejected{} = Memory.execute(proposed, reject)
    assert %Events.TagProposed{} = Memory.execute(fold([propose, reject]), propose)
  end

  test "a tagging needs an active tag and a known target kind, and is a set" do
    create = %Commands.CreateTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
    m = fold([create, add(1)])

    apply_tag = %Commands.ApplyTag{
      actor: @resident,
      at: @at,
      id: "r1",
      slug: "haven",
      target_kind: "bookmark",
      target_id: "1"
    }

    assert %Events.TagApplied{target_id: "1"} = Memory.execute(m, apply_tag)
    assert [] = Memory.execute(fold([create, add(1), apply_tag]), apply_tag)
    assert {:error, :tag_not_active} = Memory.execute(m, %{apply_tag | slug: "other"})
    assert {:error, :target_invalid} = Memory.execute(m, %{apply_tag | target_kind: "planet"})
    assert {:error, :target_invalid} = Memory.execute(m, %{apply_tag | target_id: "7"})

    retired =
      fold([
        create,
        add(1),
        apply_tag,
        %Commands.RetireTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
      ])

    assert {:error, :tag_not_active} = Memory.execute(retired, %{apply_tag | target_id: "2"})

    remove = %Commands.RemoveTagging{
      actor: @resident,
      at: @at,
      id: "r1",
      slug: "haven",
      target_kind: "bookmark",
      target_id: "1"
    }

    assert [] = Memory.execute(m, remove)
    assert %Events.TaggingRemoved{} = Memory.execute(fold([create, add(1), apply_tag]), remove)
  end

  test "a pin names the soul line it evidences; the same pin again is nothing, a different line is a new pin, and unpinning clears it" do
    m = fold([add(1)])
    pin = %Commands.PinBookmark{actor: @witness, at: @at, id: "r1", number: 1, evidences: 3}
    assert %Events.BookmarkPinned{number: 1, evidences: 3} = Memory.execute(m, pin)
    assert {:error, :evidence_invalid} = Memory.execute(m, %{pin | evidences: 0})
    assert {:error, :evidence_invalid} = Memory.execute(m, %{pin | evidences: "3"})
    assert {:error, :no_such_bookmark} = Memory.execute(m, %{pin | number: 2})

    pinned = fold([add(1), pin])
    assert [] = Memory.execute(pinned, pin)
    assert %Events.BookmarkPinned{evidences: 4} = Memory.execute(pinned, %{pin | evidences: 4})

    assert %Events.BookmarkPinned{evidences: nil} =
             Memory.execute(pinned, %{pin | evidences: nil})

    unpin = %Commands.UnpinBookmark{actor: @witness, at: @at, id: "r1", number: 1}
    assert %{bookmarks: %{1 => %{pinned: false, evidences: nil}}} = fold([add(1), pin, unpin])
  end
end
