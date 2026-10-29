defmodule Oneiroi.Kumbukumbu.MemoriesTest do
  @moduledoc "Bookmarks, tags and taggings through the exports: who may do what, numbers that are the resident's, the span, the index."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    actor = Actor.new(:resident, resident.id, "fake/model")
    steward_actor = Actor.new(:steward, steward.id)
    {:ok, key} = Kumbukumbu.main_session(resident.id, steward.id, actor)

    turns =
      for n <- 1..3 do
        ref = "t#{n}"
        at = Clock.now()

        :ok =
          Kumbukumbu.capture(
            resident.id,
            key,
            ref,
            at,
            [
              %{role: :user, content: "message #{n}", sent_at: at, actor: steward_actor},
              %{role: :assistant, content: "reply #{n}", sent_at: at, actor: actor}
            ],
            actor
          )

        ref
      end

    {:ok,
     steward: steward,
     resident: resident,
     actor: actor,
     steward_actor: steward_actor,
     key: key,
     turns: turns}
  end

  defp attrs(ctx, extra \\ %{}) do
    Map.merge(
      %{
        session_key: ctx.key,
        anchor_ref: "t2",
        line: "the moment it turned",
        summary: "what happened in turn two",
        turns_back: 1
      },
      extra
    )
  end

  test "the resident bookmarks with a minted number; the steward cannot", ctx do
    assert {:ok, 1} = Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx), ctx.actor)
    assert {:ok, 2} = Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx), ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_resident}} =
             Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx), ctx.steward_actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_turn}} =
             Kumbukumbu.add_bookmark(
               ctx.resident.id,
               attrs(ctx, %{anchor_ref: "nope"}),
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_line_invalid}} =
             Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx, %{line: ""}), ctx.actor)

    assert [%{number: 2}, %{number: 1, added_by_kind: "resident", added_by_model: "fake/model"}] =
             Kumbukumbu.bookmarks(ctx.resident.id)

    # Another resident's numbers start at one: the sequence is the resident's.
    other = Fixtures.resident!(ctx.steward)
    {:ok, other_key} = Kumbukumbu.main_session(other.id, ctx.steward.id, ctx.actor)
    at = Clock.now()
    other_actor = Actor.new(:resident, other.id, "fake/model")

    :ok =
      Kumbukumbu.capture(
        other.id,
        other_key,
        "o1",
        at,
        [
          %{role: :user, content: "x", sent_at: at, actor: ctx.steward_actor}
        ],
        other_actor
      )

    assert {:ok, 1} =
             Kumbukumbu.add_bookmark(
               other.id,
               attrs(ctx, %{session_key: other_key, anchor_ref: "o1"}),
               other_actor
             )

    assert [_, _] = Kumbukumbu.bookmarks(ctx.resident.id)
  end

  test "the span is the anchor turn and the turns before it, and grows by extension", ctx do
    assert {:ok, n} = Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx), ctx.actor)
    assert {:ok, _b, span} = Kumbukumbu.bookmark(ctx.resident.id, n)
    assert ["message 2", "reply 2"] = Enum.map(span, & &1.content)

    assert :ok = Kumbukumbu.extend_bookmark(ctx.resident.id, n, 2, ctx.actor)
    assert {:ok, %{turns_back: 2}, span} = Kumbukumbu.bookmark(ctx.resident.id, n)
    assert ["message 1", "reply 1", "message 2", "reply 2"] = Enum.map(span, & &1.content)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_span_not_grown}} =
             Kumbukumbu.extend_bookmark(ctx.resident.id, n, 2, ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_bookmark}} =
             Kumbukumbu.bookmark(ctx.resident.id, 99)
  end

  test "a pin records who pinned, and the index puts pins first and marks them", ctx do
    {:ok, a} = Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx, %{line: "first"}), ctx.actor)
    {:ok, b} = Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx, %{line: "second"}), ctx.actor)
    assert :ok = Kumbukumbu.pin_bookmark(ctx.resident.id, a, ctx.steward_actor)

    assert [%{number: ^b, pinned_at: nil}, %{number: ^a, pinned_by_kind: "steward"}] =
             Kumbukumbu.bookmarks(ctx.resident.id)

    assert %{included: [^a, ^b], left_out: 0, text: text} = Kumbukumbu.index(ctx.resident.id)
    assert text =~ "##{a} 2026-10-26 (pinned) first"
    assert :ok = Kumbukumbu.unpin_bookmark(ctx.resident.id, a, ctx.steward_actor)
    assert %{included: [^b, ^a]} = Kumbukumbu.index(ctx.resident.id)
  end

  test "the steward proposes; the resident accepts in its own words or declines with a note",
       ctx do
    assert {:ok, ref} =
             Kumbukumbu.propose_bookmark(
               ctx.resident.id,
               ctx.key,
               "t1",
               "you lit up here",
               "I think this mattered to you",
               ctx.steward_actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_steward}} =
             Kumbukumbu.propose_bookmark(ctx.resident.id, ctx.key, "t1", "x", "n", ctx.actor)

    assert [%{ref: ^ref, state: "open", note: "I think this mattered to you"}] =
             Kumbukumbu.proposals(ctx.resident.id)

    assert {:ok, n} =
             Kumbukumbu.add_bookmark(
               ctx.resident.id,
               attrs(ctx, %{anchor_ref: "t1", line: "my own words", proposal_ref: ref}),
               ctx.actor
             )

    assert [] = Kumbukumbu.proposals(ctx.resident.id)

    assert {:ok, %{line: "my own words", proposed_by_kind: "steward", anchor_ref: "t1"}, _} =
             Kumbukumbu.bookmark(ctx.resident.id, n)

    assert {:ok, ref2} =
             Kumbukumbu.propose_bookmark(
               ctx.resident.id,
               ctx.key,
               "t3",
               "and here",
               "note",
               ctx.steward_actor
             )

    assert :ok = Kumbukumbu.decline_proposal(ctx.resident.id, ref2, "not for me", ctx.actor)
    assert [] = Kumbukumbu.proposals(ctx.resident.id)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_proposal}} =
             Kumbukumbu.decline_proposal(ctx.resident.id, ref2, "again", ctx.actor)
  end

  test "tags: proposed by either, decided by the steward, applied across kinds, one query back",
       ctx do
    assert :ok =
             Kumbukumbu.propose_tag(
               ctx.resident.id,
               "haven",
               "the place we keep returning to",
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_steward}} =
             Kumbukumbu.approve_tag(ctx.resident.id, "haven", "yes", ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_tag_not_active}} =
             Kumbukumbu.apply_tag(ctx.resident.id, "haven", "conversation", ctx.key, ctx.actor)

    assert :ok = Kumbukumbu.approve_tag(ctx.resident.id, "haven", "yes", ctx.steward_actor)
    assert :ok = Kumbukumbu.create_tag(ctx.resident.id, "care", ctx.steward_actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_slug_invalid}} =
             Kumbukumbu.create_tag(ctx.resident.id, "Not Slug", ctx.steward_actor)

    assert [%{slug: "care", state: "active"}, %{slug: "haven", state: "active", note: _}] =
             Kumbukumbu.tags(ctx.resident.id)

    {:ok, n} = Kumbukumbu.add_bookmark(ctx.resident.id, attrs(ctx), ctx.actor)
    assert :ok = Kumbukumbu.apply_tag(ctx.resident.id, "haven", "bookmark", n, ctx.actor)

    assert :ok =
             Kumbukumbu.apply_tag(
               ctx.resident.id,
               "haven",
               "conversation",
               ctx.key,
               ctx.steward_actor
             )

    assert :ok = Kumbukumbu.apply_tag(ctx.resident.id, "haven", "turn", "t3", ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_target_invalid}} =
             Kumbukumbu.apply_tag(ctx.resident.id, "haven", "turn", "nope", ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_target_invalid}} =
             Kumbukumbu.apply_tag(ctx.resident.id, "haven", "bookmark", 99, ctx.actor)

    assert ["bookmark", "conversation", "turn"] =
             ctx.resident.id |> Kumbukumbu.tagged("haven") |> Enum.map(& &1.target_kind)

    assert [%{tags: ["haven"]}] = Kumbukumbu.bookmarks(ctx.resident.id)
    assert Kumbukumbu.index(ctx.resident.id).text =~ "[haven]"

    assert :ok = Kumbukumbu.remove_tagging(ctx.resident.id, "haven", "turn", "t3", ctx.actor)
    assert [_, _] = Kumbukumbu.tagged(ctx.resident.id, "haven")

    assert :ok = Kumbukumbu.retire_tag(ctx.resident.id, "haven", ctx.steward_actor)
    assert [_, _] = Kumbukumbu.tagged(ctx.resident.id, "haven")

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_tag_not_active}} =
             Kumbukumbu.apply_tag(ctx.resident.id, "haven", "turn", "t1", ctx.actor)

    assert :ok = Kumbukumbu.propose_tag(ctx.resident.id, "maybe", "why", ctx.steward_actor)
    assert :ok = Kumbukumbu.reject_tag(ctx.resident.id, "maybe", "no", ctx.steward_actor)

    assert [
             %{slug: "care"},
             %{slug: "haven", state: "retired"},
             %{slug: "maybe", state: "rejected"}
           ] =
             Kumbukumbu.tags(ctx.resident.id)
  end

  test "a compaction records the summary and the live transcript starts after it", ctx do
    assert {:ok, _s, 6} = Kumbukumbu.uncompacted(ctx.resident.id, ctx.key)
    [_ | _] = since = Kumbukumbu.since_compaction(ctx.resident.id, ctx.key)
    through = since |> Enum.map(& &1.sequence) |> Enum.max()

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_summary_empty}} =
             Kumbukumbu.compact(ctx.resident.id, ctx.key, "c1", through, "  ", ctx.actor)

    assert :ok =
             Kumbukumbu.compact(ctx.resident.id, ctx.key, "c1", through, "we talked", ctx.actor)

    assert {:ok, %{summary: "we talked", compacted_through: ^through}, 0} =
             Kumbukumbu.uncompacted(ctx.resident.id, ctx.key)

    assert [] = Kumbukumbu.recent(ctx.resident.id, ctx.key, 40)
    assert :ok = Kumbukumbu.compact(ctx.resident.id, ctx.key, "c2", through, "again", ctx.actor)
    assert {:ok, %{summary: "we talked"}, 0} = Kumbukumbu.uncompacted(ctx.resident.id, ctx.key)
  end
end
