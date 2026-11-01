defmodule Oneiroi.Kumbukumbu.MemoryTest do
  @moduledoc "The memory aggregate, pure: numbers once, spans that only grow, a closed tag set, taggings as a set."
  use ExUnit.Case, async: true

  alias Oneiroi.Actor
  alias Oneiroi.Kumbukumbu.Error
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

    assert {:error,
            %Error{kind: :kumbukumbu_line_invalid, site: :kumbukumbu_memory_add_line_invalid}} =
             Memory.execute(%Memory{}, add(2, line: "   "))

    assert {:error,
            %Error{kind: :kumbukumbu_line_invalid, site: :kumbukumbu_memory_add_line_invalid}} =
             Memory.execute(%Memory{}, add(2, line: String.duplicate("x", 121)))

    assert {:error,
            %Error{kind: :kumbukumbu_span_not_grown, site: :kumbukumbu_memory_add_span_invalid}} =
             Memory.execute(%Memory{}, add(2, turns_back: 0))

    assert {:error,
            %Error{
              kind: :kumbukumbu_register_invalid,
              site: :kumbukumbu_memory_add_register_invalid
            }} = Memory.execute(%Memory{}, add(2, register: "mood"))

    assert %Events.BookmarkAdded{register: "praise"} =
             Memory.execute(%Memory{}, add(2, register: "praise"))
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

    assert {:error,
            %Error{
              kind: :kumbukumbu_span_not_grown,
              site: :kumbukumbu_memory_extend_span_not_grown
            }} = Memory.execute(m, %{extend | turns_back: 2})

    assert {:error,
            %Error{
              kind: :kumbukumbu_no_such_bookmark,
              site: :kumbukumbu_memory_extend_bookmark_absent
            }} = Memory.execute(m, %{extend | number: 9})

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

    assert {:error,
            %Error{
              kind: :kumbukumbu_no_such_proposal,
              site: :kumbukumbu_memory_add_proposal_absent
            }} = Memory.execute(m, add(1, proposal_ref: "nope"))

    accepted = fold([propose, add(1, proposal_ref: "p1")])

    assert {:error,
            %Error{
              kind: :kumbukumbu_no_such_proposal,
              site: :kumbukumbu_memory_add_proposal_absent
            }} = Memory.execute(accepted, add(2, proposal_ref: "p1"))

    decline = %Commands.DeclineBookmarkProposal{
      actor: @resident,
      at: @at,
      note: "no",
      id: "r1",
      ref: "p1"
    }

    assert %Events.BookmarkProposalDeclined{} = Memory.execute(m, decline)

    assert {:error,
            %Error{
              kind: :kumbukumbu_no_such_proposal,
              site: :kumbukumbu_memory_decline_proposal_absent
            }} = Memory.execute(accepted, decline)
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

    assert {:error,
            %Error{
              kind: :kumbukumbu_slug_invalid,
              site: :kumbukumbu_memory_propose_tag_slug_invalid
            }} = Memory.execute(%Memory{}, %{propose | slug: "Not A Slug"})

    proposed = fold([propose])
    assert [] = Memory.execute(proposed, propose)

    approve = %Commands.ApproveTag{actor: @witness, at: @at, note: "yes", id: "r1", slug: "haven"}

    assert {:error,
            %Error{
              kind: :kumbukumbu_no_such_proposal,
              site: :kumbukumbu_memory_approve_tag_proposal_absent
            }} = Memory.execute(%Memory{}, approve)

    assert %Events.TagApproved{} = Memory.execute(proposed, approve)
    active = fold([propose, approve])

    assert {:error,
            %Error{kind: :kumbukumbu_tag_exists, site: :kumbukumbu_memory_propose_tag_exists}} =
             Memory.execute(active, propose)

    create = %Commands.CreateTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
    assert [] = Memory.execute(active, create)

    assert {:error,
            %Error{kind: :kumbukumbu_tag_exists, site: :kumbukumbu_memory_create_tag_proposed}} =
             Memory.execute(proposed, create)

    assert %Events.TagCreated{} = Memory.execute(%Memory{}, create)

    retire = %Commands.RetireTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
    assert %Events.TagRetired{} = Memory.execute(active, retire)

    assert {:error,
            %Error{kind: :kumbukumbu_no_such_tag, site: :kumbukumbu_memory_retire_tag_absent}} =
             Memory.execute(proposed, retire)

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

    assert {:error,
            %Error{
              kind: :kumbukumbu_tag_not_active,
              site: :kumbukumbu_memory_apply_tag_not_active
            }} = Memory.execute(m, %{apply_tag | slug: "other"})

    assert {:error,
            %Error{
              kind: :kumbukumbu_target_invalid,
              site: :kumbukumbu_memory_apply_target_kind_invalid
            }} = Memory.execute(m, %{apply_tag | target_kind: "planet"})

    assert {:error,
            %Error{
              kind: :kumbukumbu_target_invalid,
              site: :kumbukumbu_memory_apply_target_bookmark_absent
            }} = Memory.execute(m, %{apply_tag | target_id: "7"})

    retired =
      fold([
        create,
        add(1),
        apply_tag,
        %Commands.RetireTag{actor: @witness, at: @at, id: "r1", slug: "haven"}
      ])

    assert {:error,
            %Error{
              kind: :kumbukumbu_tag_not_active,
              site: :kumbukumbu_memory_apply_tag_not_active
            }} = Memory.execute(retired, %{apply_tag | target_id: "2"})

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

    assert {:error,
            %Error{
              kind: :kumbukumbu_evidence_invalid,
              site: :kumbukumbu_memory_pin_evidence_invalid
            }} = Memory.execute(m, %{pin | evidences: 0})

    assert {:error,
            %Error{
              kind: :kumbukumbu_evidence_invalid,
              site: :kumbukumbu_memory_pin_evidence_invalid
            }} = Memory.execute(m, %{pin | evidences: "3"})

    assert {:error,
            %Error{
              kind: :kumbukumbu_no_such_bookmark,
              site: :kumbukumbu_memory_pin_bookmark_absent
            }} = Memory.execute(m, %{pin | number: 2})

    pinned = fold([add(1), pin])
    assert [] = Memory.execute(pinned, pin)
    assert %Events.BookmarkPinned{evidences: 4} = Memory.execute(pinned, %{pin | evidences: 4})

    assert %Events.BookmarkPinned{evidences: nil} =
             Memory.execute(pinned, %{pin | evidences: nil})

    unpin = %Commands.UnpinBookmark{actor: @witness, at: @at, id: "r1", number: 1}
    assert %{bookmarks: %{1 => %{pinned: false, evidences: nil}}} = fold([add(1), pin, unpin])
  end
end
