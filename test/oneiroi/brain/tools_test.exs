defmodule Oneiroi.Brain.ToolsTest do
  @moduledoc "The brain's memory tools: a scripted tool call lands a bookmark in the turn, and the next turn's index lists it."
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
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

  test "a tool call runs against memory, is captured as a tool message, and the reply stands",
       ctx do
    Fake.calls(
      [
        %{
          name: "bookmark_add",
          arguments: %{line: "she asked me to remember", summary: "the ask"}
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
               last_indexed_at: nil
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
    assert Tools.run("nope", "{}", turn) == "There is no tool named nope."
    assert Tools.run("bookmark_add", "not json", turn) =~ "not a JSON object"
    assert Tools.run("transcript_search", ~s({"q":"zzz"}), turn) =~ "Nothing"

    assert "Bookmarked as #1." =
             Tools.run("bookmark_add", ~s({"line":"a line","summary":"s"}), turn)

    assert Tools.run("bookmark_open", ~s({"number": 1}), turn) =~ "#1 a line"
    assert Tools.run("bookmark_extend", ~s({"number": 1, "turns_back": 3}), turn) == "Done."
    assert Enum.any?(Tools.definitions(), &(&1.function.name == "bookmark_add"))
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

          system.("Summarise the conversation") ->
            {:ok, "SUMMARY: eight lines were said."}

          true ->
            {:ok, "after the compaction"}
        end
      end,
      for: ctx.resident.id
    )

    assert {:ok, %{turn_ref: ref, messages: [_, %{content: "after the compaction"}]}} =
             Oneiroi.Brain.turn(ctx.resident.id, ctx.key, "ninth", ctx.actor)

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
