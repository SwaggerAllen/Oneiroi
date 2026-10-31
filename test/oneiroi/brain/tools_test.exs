defmodule Oneiroi.Brain.ToolsTest do
  @moduledoc "The brain's memory tools: a scripted tool call lands a bookmark in the turn, and the next turn's index lists it."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake

  @once ~s({"line":"keep this","summary":"s"})

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)
    {:ok, witness: witness, resident: resident, key: key, actor: actor}
  end

  test "a tool call runs against memory, is captured as a tool message, and the reply stands",
       ctx do
    Fake.calls(
      [
        %{
          name: "bookmark_add",
          arguments: %{
            line: "she asked me to remember",
            summary: "the ask",
            register: "instruction"
          }
        }
      ],
      "I will remember.",
      for: ctx.resident.id
    )

    assert {:ok, %{turn_ref: ref, messages: messages, drew_on: 4}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "remember this", ctx.actor)

    assert [:user, :tool, :assistant] = Enum.map(messages, & &1.role)

    assert Enum.at(messages, 1).content =~ "bookmark_add(" and
             Enum.at(messages, 1).content =~ "Bookmarked as #1."

    assert List.last(messages).content == "I will remember."

    assert [
             %{
               number: 1,
               anchor_ref: ^ref,
               line: "she asked me to remember",
               last_indexed_at: nil,
               register: "instruction"
             }
           ] =
             Kumbukumbu.bookmarks(ctx.resident.id)

    {:ok, _s, transcript} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert ["user", "tool", "assistant"] = Enum.map(transcript, & &1.role)

    # The next turn's index lists it, the injection carries the verbatim
    # text and the number, and the row records that it was in the index.
    Fake.clear(for: ctx.resident.id)

    assert {:ok, %{turn_ref: ref2}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "and now?", ctx.actor)

    assert [
             %{label: "prompt"},
             %{label: "AGENTS.md"},
             %{label: "index", text: text},
             %{label: "transcript"}
           ] =
             Kumbukumbu.injections({:account, ctx.witness.id}, ref2)

    assert text =~ "#1 2026-10-26 she asked me to remember"
    assert [%{last_indexed_at: %DateTime{}}] = Kumbukumbu.bookmarks(ctx.resident.id)
    assert {:ok, _b, span} = Kumbukumbu.bookmark(ctx.resident.id, 1)

    assert ["remember this", "I will remember."] =
             span |> Enum.reject(&(&1.role == "tool")) |> Enum.map(& &1.content)
  end

  # The fixture's turn 2 used four tools and every turn after it was
  # refused: the stored `tool` rows went back bare, answering no call.
  test "the turn after one that used tools sends each use back as a call and its answer", ctx do
    Fake.calls(
      [
        # One object twice over, as fixture run 41248366617's journal_add
        # arrived; the fake refuses it on the wire, as that provider did.
        %{name: "bookmark_add", arguments: @once <> @once},
        %{name: "figure_list", arguments: "null"}
      ],
      "Kept.",
      for: ctx.resident.id
    )

    assert {:ok, %{messages: first}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "keep this", ctx.actor)

    assert [:user, :tool, :tool, :assistant] = Enum.map(first, & &1.role)
    # The transcript keeps what the model sent; the wire gets one object.
    assert Enum.at(first, 1).content =~ @once <> @once

    test = self()

    Fake.script(
      fn %{messages: shown} ->
        send(test, {:shown, shown})
        {:ok, "still here"}
      end,
      for: ctx.resident.id
    )

    assert {:ok, %{messages: [_, %{content: "still here"}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "and now?", ctx.actor)

    assert_received {:shown, shown}
    replayed = Enum.drop_while(shown, &(&1.content != "keep this"))

    assert [
             %{role: :user, content: "keep this"},
             %{role: :assistant, tool_calls: [%{id: a, function: %{name: "bookmark_add"} = f}]},
             %{role: :tool, tool_call_id: a, content: "Bookmarked as #1."},
             %{
               role: :assistant,
               tool_calls: [%{id: b, function: %{name: "figure_list", arguments: "{}"}}]
             },
             %{role: :tool, tool_call_id: b, content: "No figures yet."},
             %{role: :assistant, content: "Kept."},
             %{role: :user, content: "and now?"}
           ] = replayed

    assert a != b
    assert f.arguments == @once
  end

  test "what goes back on the wire is one JSON object, whatever the model sent" do
    assert Tools.wire_arguments(@once) == @once
    assert Tools.wire_arguments(@once <> @once) == @once
    assert Tools.wire_arguments(" " <> @once <> " ") == " " <> @once <> " "

    for none <- ["null", "", "not json", "[1]", @once <> ~s({"other":1})],
        do: assert(Tools.wire_arguments(none) == "{}", inspect(none))
  end

  test "a habit named with seed number 0 graduates nothing and is named", ctx do
    turn = %{
      resident_id: ctx.resident.id,
      session_key: ctx.key,
      turn_ref: "t-live",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.resident.id, "fake/model")
    }

    for n <- ["0", "-0", "-3"] do
      args = ~s({"name":"brief #{n}","stance":"keep","words":["brief"],"seed_number":#{n}})
      assert Tools.run("habit_define", args, turn) =~ "Named as habit #"
    end
  end

  test "the tools answer in words, misuse included", ctx do
    turn = %{
      resident_id: ctx.resident.id,
      session_key: ctx.key,
      turn_ref: "t-live",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.resident.id, "fake/model")
    }

    assert Tools.run("tag_list", "{}", turn) =~ "empty"
    assert "Done." = Tools.run("tag_propose", ~s({"slug":"haven","note":"why"}), turn)
    assert Tools.run("tag_list", "{}", turn) == "haven (proposed)"

    assert Tools.run(
             "tag_apply",
             ~s({"slug":"haven","target_kind":"conversation","target_id":"#{ctx.key}"}),
             turn
           ) =~ "only an active tag"

    assert Tools.run("bookmark_open", ~s({"number": 7}), turn) =~ "no bookmark has that number"
    assert Tools.run("nope", "{}", turn) == "Not done: there is no tool named nope."
    assert Tools.run("bookmark_add", "not json", turn) =~ "not a JSON object"
    assert Tools.run("transcript_search", ~s({"q":"zzz"}), turn) =~ "Nothing"

    assert "Bookmarked as #1." =
             Tools.run("bookmark_add", ~s({"line":"a line","summary":"s"}), turn)

    assert Tools.run("bookmark_open", ~s({"number": 1}), turn) =~ "#1 a line"
    assert Tools.run("bookmark_extend", ~s({"number": 1, "turns_back": 3}), turn) == "Done."
    assert Enum.any?(Tools.definitions(), &(&1.function.name == "bookmark_add"))
  end

  # Fixture runs of 10-31: `commitment_list(null)` refused, then the
  # model told its witness it held no commitments; `bookmark_add` with
  # one object twice over refused, and no bookmark made.
  test "a tool taking nothing takes null or nothing, and one object repeated is that object",
       ctx do
    turn = %{
      resident_id: ctx.resident.id,
      session_key: ctx.key,
      turn_ref: "t-live",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.resident.id, "fake/model")
    }

    for blank <- ["null", "", " null "], do: assert(Tools.run("tag_list", blank, turn) =~ "empty")

    once = ~s({"line":"twice over","summary":"s"})
    assert "Bookmarked as #1." = Tools.run("bookmark_add", once <> once, turn)

    assert Tools.run("bookmark_add", once <> ~s({"line":"other","summary":"s"}), turn) ==
             "Not done: the arguments were not a JSON object."

    assert Tools.run("bookmark_add", "[1]", turn) =~ "Not done: "
  end

  test "a refusal reads as two sentences, marked not done", ctx do
    turn = %{
      resident_id: ctx.resident.id,
      session_key: ctx.key,
      turn_ref: "t-live",
      started_at: Clock.now(),
      resident: Actor.new(:resident, ctx.resident.id, "fake/model")
    }

    said = Tools.run("bookmark_open", ~s({"number": 7}), turn)
    assert String.starts_with?(said, "Not done: ")
    assert said =~ ~r/\. [A-Z]/
  end

  test "a session that outgrows its window is compacted at the next turn: flush, summary, record",
       ctx do
    at = Clock.now()
    resident_actor = Actor.new(:resident, ctx.resident.id, "fake/model")

    messages =
      for n <- 1..8 do
        role = if rem(n, 2) == 1, do: :user, else: :assistant
        %{role: role, content: "line #{n}", sent_at: at, actor: resident_actor}
      end

    :ok = Kumbukumbu.capture(ctx.resident.id, ctx.key, "big", at, messages, resident_actor)

    test = self()

    Fake.script(
      fn %{messages: msgs} ->
        system = fn prefix ->
          Enum.any?(msgs, &(&1.role == :system and String.starts_with?(&1.content, prefix)))
        end

        cond do
          Enum.any?(msgs, &(&1.role == :tool)) ->
            {:ok, "Kept one."}

          system.("This conversation is about to be compacted") ->
            {:calls,
             [
               %{
                 name: "bookmark_add",
                 arguments: %{line: "worth keeping", summary: "from the flush"}
               }
             ]}

          system.("You are the compaction machinery") ->
            prompt = Enum.find(msgs, &(&1.role == :system))
            send(test, {:compaction, prompt.content})
            {:ok, "SUMMARY: eight lines were said."}

          true ->
            {:ok, "after the compaction"}
        end
      end,
      for: ctx.resident.id
    )

    assert {:ok, %{turn_ref: ref, messages: [_, %{content: "after the compaction"}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "ninth", ctx.actor)

    # The summary keeps movement, not only state (P34): the prompt asks for it.
    assert_received {:compaction, prompt}
    assert prompt =~ "where it can resume"
    assert prompt =~ "dormant, not abandoned"

    assert {:ok, %{summary: "SUMMARY: eight lines were said.", compacted_through: through}, 2} =
             Kumbukumbu.uncompacted(ctx.resident.id, ctx.key)

    assert through > 0
    assert [%{line: "worth keeping", anchor_ref: ^ref}] = Kumbukumbu.bookmarks(ctx.resident.id)

    labels =
      ctx.resident.id
      |> then(&Kumbukumbu.injections({:resident, &1}, ref))
      |> Enum.map(& &1.label)

    assert ["prompt", "AGENTS.md", "index", "summary", "transcript"] = labels

    # The history and the whole transcript are both intact: compaction deletes nothing.
    {:ok, _s, transcript} = Kumbukumbu.transcript({:account, ctx.witness.id}, ctx.key)
    assert length(transcript) == 10

    assert ["user", "assistant"] =
             ctx.resident.id |> Kumbukumbu.recent(ctx.key, 40) |> Enum.map(& &1.role)

    # The summary reaches the next turn as machine-state, marked as the
    # machinery's in the context itself (spec §5, P1 and P24).
    test = self()

    Fake.script(
      fn %{messages: shown} ->
        send(test, {:shown, shown})
        {:ok, "read it"}
      end,
      for: ctx.resident.id
    )

    assert {:ok, _} = Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "tenth", ctx.actor)
    assert_received {:shown, shown}

    assert [%{content: summary}] =
             Enum.filter(shown, &(&1.role == :system and &1.content =~ "SUMMARY: eight lines"))

    assert String.starts_with?(summary, "# Compaction summary: machine-state")
  end

  test "a session with a tool's use in it compacts: the flush sees the call and its answer, the summary sees words",
       ctx do
    at = Clock.now()
    resident_actor = Actor.new(:resident, ctx.resident.id, "fake/model")

    messages =
      for n <- 1..8 do
        case rem(n, 3) do
          1 ->
            %{role: :user, content: "line #{n}", sent_at: at, actor: resident_actor}

          2 ->
            %{role: :tool, content: "tag_list({}) -> #{n}", sent_at: at, actor: resident_actor}

          0 ->
            %{role: :assistant, content: "line #{n}", sent_at: at, actor: resident_actor}
        end
      end

    :ok = Kumbukumbu.capture(ctx.resident.id, ctx.key, "big", at, messages, resident_actor)
    test = self()

    Fake.script(
      fn %{messages: msgs} ->
        system = fn prefix ->
          Enum.any?(msgs, &(&1.role == :system and String.starts_with?(&1.content, prefix)))
        end

        cond do
          system.("You are the compaction machinery") ->
            send(test, {:summarised, msgs})
            {:ok, "SUMMARY: tools were used."}

          system.("This conversation is about to be compacted") ->
            send(test, {:flushed, msgs})
            {:ok, "nothing to keep"}

          true ->
            {:ok, "after the compaction"}
        end
      end,
      for: ctx.resident.id
    )

    assert {:ok, %{messages: [_, %{content: "after the compaction"}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "ninth", ctx.actor)

    assert {:ok, %{summary: "SUMMARY: tools were used."}, _} =
             Kumbukumbu.uncompacted(ctx.resident.id, ctx.key)

    assert_received {:flushed, flushed}
    assert [%{tool_call_id: id, content: "2"} | _] = Enum.filter(flushed, &(&1.role == :tool))
    assert Enum.any?(flushed, &match?(%{tool_calls: [%{id: ^id}]}, &1))

    assert_received {:summarised, summarised}
    refute Enum.any?(summarised, &(&1.role == :tool or Map.has_key?(&1, :tool_calls)))

    assert Enum.any?(
             summarised,
             &(&1.role == :assistant and &1.content == "tag_list({}) -> 2")
           )
  end

  test "a flush that fails leaves the session uncompacted and the turn goes on", ctx do
    at = Clock.now()
    resident_actor = Actor.new(:resident, ctx.resident.id, "fake/model")

    messages =
      for n <- 1..8, do: %{role: :user, content: "line #{n}", sent_at: at, actor: resident_actor}

    :ok = Kumbukumbu.capture(ctx.resident.id, ctx.key, "big", at, messages, resident_actor)

    Fake.script(
      fn %{messages: msgs} ->
        if Enum.any?(
             msgs,
             &(&1.role == :system and String.starts_with?(&1.content, "This conversation"))
           ),
           do: {:error, {:transport, :scripted}},
           else: {:ok, "still here"}
      end,
      for: ctx.resident.id
    )

    assert {:ok, %{messages: [_, %{content: "still here"}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "ninth", ctx.actor)

    assert {:ok, %{summary: nil, compacted_through: 0}, 10} =
             Kumbukumbu.uncompacted(ctx.resident.id, ctx.key)
  end
end
