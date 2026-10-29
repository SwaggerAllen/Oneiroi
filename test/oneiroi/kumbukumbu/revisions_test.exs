defmodule Oneiroi.Kumbukumbu.RevisionsTest do
  @moduledoc "Revisions (F13) through the exports and the brain: a fact by either party holds at once, a stance by the resident too, a stance by the steward is a proposal the resident accepts or declines with a note; revision adds beside the memory and never overwrites it."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho

  setup do
    steward = Fixtures.account!()
    resident = Fixtures.resident!(steward)
    actor = Actor.new(:steward, steward.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(steward.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, steward.id, actor)
    Model.clear()
    Honcho.clear(for: resident.id)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        resident.id,
        %{
          session_key: key,
          anchor_ref: "t1",
          line: "the tea was Assam",
          summary: "we talked tea",
          turns_back: 1,
          anchor_at: Clock.now()
        },
        brain
      )

    on_exit(fn ->
      Model.clear(for: resident.id)
      Honcho.clear(for: resident.id)
    end)

    {:ok, id: resident.id, actor: actor, brain: brain, key: key, bookmark: n}
  end

  test "facts apply from either party, stances from the resident; the steward's stance is proposed and the resident decides; the words stand beside the revision",
       ctx do
    id = ctx.id
    n = ctx.bookmark

    assert {:ok, %{number: 1, state: "applied"}} =
             Kumbukumbu.revise(
               id,
               %{
                 target_kind: "bookmark",
                 target_id: n,
                 kind: "fact",
                 text: "It was Darjeeling.",
                 note: "I bought it"
               },
               ctx.actor
             )

    assert {:ok, %{number: 2, state: "applied"}} =
             Kumbukumbu.revise(
               id,
               %{
                 target_kind: "bookmark",
                 target_id: n,
                 kind: "stance",
                 text: "I liked it less than I said.",
                 note: "on reflection"
               },
               ctx.brain
             )

    assert {:ok, %{number: 3, state: "proposed"}} =
             Kumbukumbu.revise(
               id,
               %{
                 target_kind: "bookmark",
                 target_id: n,
                 kind: "stance",
                 text: "You loved it.",
                 note: "you said so twice"
               },
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_revision_kind_invalid}} =
             Kumbukumbu.revise(
               id,
               %{target_kind: "bookmark", target_id: n, kind: "opinion", text: "x", note: "n"},
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_revision_text_invalid}} =
             Kumbukumbu.revise(
               id,
               %{target_kind: "bookmark", target_id: n, kind: "fact", text: " ", note: "n"},
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_target_invalid}} =
             Kumbukumbu.revise(
               id,
               %{target_kind: "bookmark", target_id: 99, kind: "fact", text: "x", note: "n"},
               ctx.actor
             )

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_target_invalid}} =
             Kumbukumbu.revise(
               id,
               %{target_kind: "dream", target_id: "1", kind: "fact", text: "x", note: "n"},
               ctx.actor
             )

    # The resident decides; the steward may not.
    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_not_the_resident}} =
             Kumbukumbu.accept_revision(id, 3, "fine", ctx.actor)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_revision}} =
             Kumbukumbu.accept_revision(id, 1, "fine", ctx.brain)

    assert :ok = Kumbukumbu.decline_revision(id, 3, "I did not", ctx.brain)

    assert {:error, %Kumbukumbu.Error{kind: :kumbukumbu_no_such_revision}} =
             Kumbukumbu.accept_revision(id, 3, "fine", ctx.brain)

    assert {:ok, %{number: 4, state: "proposed"}} =
             Kumbukumbu.revise(
               id,
               %{
                 target_kind: "bookmark",
                 target_id: n,
                 kind: "stance",
                 text: "You liked it well enough.",
                 note: "softer"
               },
               ctx.actor
             )

    assert :ok = Kumbukumbu.accept_revision(id, 4, "that is fair", ctx.brain)

    assert [
             %{
               number: 4,
               state: "applied",
               by_kind: "steward",
               note: "softer",
               decision_note: "that is fair"
             },
             %{number: 3, state: "declined", decision_note: "I did not"},
             %{number: 2, state: "applied", by_kind: "resident"},
             %{number: 1, state: "applied", by_kind: "steward", kind: "fact"}
           ] =
             Kumbukumbu.revisions(id)

    # The bookmark's own words are unchanged; the revisions sit beside them.
    assert {:ok, %{line: "the tea was Assam", summary: "we talked tea"}, _span} =
             Kumbukumbu.bookmark(id, n)

    assert [%{number: 1}, %{number: 2}, %{number: 4}] = Kumbukumbu.revisions_of(id, "bookmark", n)
  end

  test "the brain revises, lists and decides through its tools, and sees revisions when it opens a bookmark",
       ctx do
    id = ctx.id
    n = ctx.bookmark

    {:ok, %{number: 1, state: "proposed"}} =
      Kumbukumbu.revise(
        id,
        %{
          target_kind: "bookmark",
          target_id: n,
          kind: "stance",
          text: "You loved it.",
          note: "twice"
        },
        ctx.actor
      )

    Model.calls(
      [
        %{
          name: "revision_add",
          arguments: %{
            target_kind: "bookmark",
            target_id: to_string(n),
            kind: "fact",
            text: "It was the second cup.",
            note: "I counted"
          }
        },
        %{name: "revision_accept", arguments: %{number: 1, note: "fair"}},
        %{name: "revision_list", arguments: %{}},
        %{name: "bookmark_open", arguments: %{number: n}}
      ],
      "Done.",
      for: id
    )

    assert {:ok, %{messages: messages}} =
             Oneiroi.Brain.turn(id, ctx.key, "about the tea", ctx.actor)

    tools = for %{role: :tool, content: c} <- messages, do: c
    assert String.ends_with?(Enum.at(tools, 0), "-> Revision 2 applied.")
    assert String.ends_with?(Enum.at(tools, 1), "-> Done.")

    assert Enum.at(tools, 2) =~
             "Revision 1 (stance, applied, by the steward) on bookmark/#{n}: You loved it. (twice)"

    assert Enum.at(tools, 3) =~ "##{n} the tea was Assam" and
             Enum.at(tools, 3) =~ "Revision 2 (fact, applied, by the resident)"
  end
end
