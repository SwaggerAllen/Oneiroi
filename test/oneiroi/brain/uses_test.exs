defmodule Oneiroi.Brain.UsesTest do
  @moduledoc "What retrieval did with each target in a turn (kumbukumbu #43): considered, returned and used, read off the sections, the tools and the replies, recorded once a turn, and read back by both parties."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Uses
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Nisaba.Provider.Request

  describe "the uses, pure" do
    test "the index's ranked and listed, the near-misses considered, and each other section's refs as their kind" do
      uses =
        Uses.from_injections([
          %{label: "prompt", refs: nil},
          %{label: "index", refs: [3, 2]},
          %{label: "near-miss", considered: [1]},
          %{label: "madeleine", refs: [9]},
          %{label: "character", refs: [4]},
          %{label: "promised", refs: [1]},
          %{label: "movement", refs: ["t-1"]}
        ])

      assert uses == [
               %{target: "bookmark/3", stage: "considered", via: "index"},
               %{target: "bookmark/3", stage: "returned", via: "index"},
               %{target: "bookmark/2", stage: "considered", via: "index"},
               %{target: "bookmark/2", stage: "returned", via: "index"},
               %{target: "bookmark/1", stage: "considered", via: "index"},
               %{target: "bookmark/9", stage: "considered", via: "madeleine"},
               %{target: "bookmark/9", stage: "returned", via: "madeleine"},
               %{target: "habit/4", stage: "considered", via: "character"},
               %{target: "habit/4", stage: "returned", via: "character"},
               %{target: "commitment/1", stage: "considered", via: "promised"},
               %{target: "commitment/1", stage: "returned", via: "promised"}
             ]
    end

    test "a tool's reads are used, its searches and lists returned, and a call not done is nothing" do
      used = &[%{target: &1, stage: "used", via: &2}]

      assert Uses.from_call("bookmark_open", %{"number" => 42}, "#42 the line", "lily") ==
               used.("bookmark/42", "bookmark_open")

      assert Uses.from_call("library_read", %{"path" => "writing/the-bake-off.md"}, "x", "lily") ==
               used.("writing/the-bake-off", "library_read")

      assert Uses.from_call("library_read", %{"path" => "research/task/source.md#3"}, "x", "lily") ==
               used.("research/task/source", "library_read")

      assert Uses.from_call("library_read", %{"path" => "pocket-andrew.md"}, "x", "lily") ==
               used.("keepsake/pocket-andrew", "library_read")

      assert Uses.from_call(
               "library_read",
               %{"path" => "lily:keepsake/pocket-andrew"},
               "x",
               "lily"
             ) ==
               used.("keepsake/pocket-andrew", "library_read")

      assert Uses.from_call("writing_get", %{"slug" => "pond"}, "x", "lily") ==
               used.("writing/pond", "writing_get")

      assert Uses.from_call(
               "bookmark_open",
               %{"number" => 42},
               "Not done: no bookmark has that number.",
               "lily"
             ) ==
               []

      hits =
        "[writing/pond.md] passage 1 of Pond: water\n[writing/pond.md] passage 2 of Pond: more\n[wiki/bread.md] passage 1 of Bread: flour"

      assert Uses.from_call("library_search", %{"q" => "water"}, hits, "lily") == [
               %{target: "writing/pond", stage: "considered", via: "library_search"},
               %{target: "writing/pond", stage: "returned", via: "library_search"},
               %{target: "wiki/bread", stage: "considered", via: "library_search"},
               %{target: "wiki/bread", stage: "returned", via: "library_search"}
             ]

      found = "[s1/t1] user: hello\n[s1/t2] assistant: hi\n[s2/t9] user: hello again"

      assert Uses.from_call("transcript_search", %{"q" => "hello"}, found, "lily")
             |> Enum.filter(&(&1.stage == "returned"))
             |> Enum.map(& &1.target) == ["transcript/s1", "transcript/s2"]

      listed =
        "#5 2026-10-30 a line\n#4 2026-10-29 (pinned) another\nNothing further back matches."

      assert Uses.from_call("bookmark_list", %{}, listed, "lily") == [
               %{target: "bookmark/5", stage: "returned", via: "bookmark_list"},
               %{target: "bookmark/4", stage: "returned", via: "bookmark_list"}
             ]

      assert Uses.from_call(
               "document_write",
               %{"content" => "see lily:bookmark/7 and max:bookmark/1"},
               "Written",
               "lily"
             ) ==
               used.("bookmark/7", "document_write")
    end

    test "a reply's citations of the resident's own records are used, once each; another resident's are not" do
      text =
        "As lily:bookmark/1 says, and lily:writing/pond#2, and lily:bookmark/1 again; not max:bookmark/2."

      assert Uses.from_reply(text, "lily") == [
               %{target: "bookmark/1", stage: "used", via: "reply"},
               %{target: "writing/pond", stage: "used", via: "reply"}
             ]

      assert Uses.from_reply(text, nil) == []
    end
  end

  describe "the ledger" do
    setup do
      witness = Fixtures.account!()
      resident = Fixtures.resident!(witness)
      actor = Actor.new(:witness, witness.id)
      :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
      {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
      on_exit(fn -> Fake.clear(for: resident.id) end)
      {:ok, witness: witness, resident: resident, key: key, actor: actor}
    end

    test "a turn records what its index returned, what it opened and what its reply cited; both parties read the counts",
         ctx do
      id = ctx.resident.id
      slug = ctx.resident.slug

      Fake.calls(
        [%{name: "bookmark_add", arguments: %{line: "the garden", summary: "s"}}],
        "Kept.",
        for: id
      )

      {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "remember the garden", ctx.actor)
      # The first turn's index was empty, and writing a bookmark is not retrieving one.
      assert Kumbukumbu.retrieval({:resident, id}, []) == []

      Fake.clear(for: id)

      # `Fake.calls/3` answers in words once any tool message is in the
      # request, and the first turn's is in this one's history: this
      # turn calls while its own last message is not a tool's answer.
      Fake.script(
        fn %Request{messages: messages} ->
          if List.last(messages)[:role] == :tool,
            do: {:ok, "The garden, as #{slug}:bookmark/1 has it."},
            else: {:calls, [%{name: "bookmark_open", arguments: %{number: 1}}]}
        end,
        for: id
      )

      {:ok, _} = Oneiroi.Brain.turn(id, ctx.key, "what did we say about the garden?", ctx.actor)

      assert [
               %{
                 target: "bookmark/1",
                 # The index listed it and the madeleine surfaced it: two
                 # sections returned it, each having considered it.
                 considered: 2,
                 returned: 2,
                 used: 2,
                 last_used_at: %DateTime{},
                 last_returned_at: %DateTime{}
               }
             ] = Kumbukumbu.retrieval({:resident, id}, kind: "bookmark")

      # The resident reads the same numbers as the witness: the audit is two-party.
      turn = %{
        resident_id: id,
        session_key: ctx.key,
        turn_ref: "t-read",
        resident: Actor.new(:resident, id)
      }

      assert Tools.run("memory_use", ~s({}), turn) =~
               ~r/^bookmark\/1: considered 2, returned 2, used 2; last used \d{4}-\d\d-\d\d; last returned \d{4}-\d\d-\d\d\n1 of 1 targets shown\.$/

      assert Tools.run("memory_use", ~s({"order":"unused"}), turn) ==
               "Nothing is counted there yet."

      assert Tools.run("memory_use", ~s({"kind":"writing"}), turn) ==
               "Nothing is counted there yet."

      assert [%{target: "bookmark/1", used: 2}] =
               Kumbukumbu.retrieval({:account, ctx.witness.id}, [])
    end

    test "a runtime's call inside its open turn records its own uses; outside a turn it records none",
         ctx do
      id = ctx.resident.id
      turn_ref = Kumbukumbu.turn_ref()
      :ok = Kumbukumbu.start_turn(id, ctx.key, turn_ref, Actor.new(:resident, id))

      turn = %{
        resident_id: id,
        session_key: ctx.key,
        turn_ref: turn_ref,
        resident: Actor.new(:resident, id)
      }

      :ok = Tools.record_uses("bookmark_open", ~s({"number":7}), "#7 a line", turn)

      :ok =
        Tools.record_uses("bookmark_open", ~s({"number":7}), "#7 a line", %{turn | turn_ref: nil})

      :ok =
        Tools.record_uses(
          "bookmark_open",
          ~s({"number":7}),
          "Not done: no bookmark has that number.",
          turn
        )

      assert [%{target: "bookmark/7", used: 1, returned: 0}] =
               Kumbukumbu.retrieval({:resident, id}, [])
    end
  end
end
