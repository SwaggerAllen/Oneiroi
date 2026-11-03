defmodule Oneiroi.Brain.OracleTest do
  @moduledoc """
  The oracle (brain #49, seshat #34): an invocation of the resident
  asked one named question, with her whole memory and every read tool,
  writing nothing but its answer; long sources read in parts first; the
  answer under oracle/ with its confidence, found deliberately, and the
  asking conversation told by letter.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Oracle
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, actor)
    on_exit(fn -> Fake.clear(for: resident.id) end)

    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        resident.id,
        key,
        "anchor",
        at,
        [%{role: :user, content: "the heron by the weir at dawn", sent_at: at, actor: actor}],
        brain
      )

    {:ok, 1} =
      Kumbukumbu.add_bookmark(
        resident.id,
        %{session_key: key, anchor_ref: "anchor", line: "the heron by the weir", summary: "dawn"},
        brain
      )

    turn = %{
      resident_id: resident.id,
      session_key: key,
      turn_ref: "t-ask",
      started_at: Clock.now(),
      resident: brain
    }

    {:ok, id: resident.id, key: key, actor: actor, brain: brain, turn: turn}
  end

  defp ask(ctx, questions) do
    Tools.run("oracle_ask", Jason.encode!(%{questions: questions}), ctx.turn)
  end

  test "a dispatch numbers its named questions, records who asked, and is found deliberately",
       ctx do
    assert ask(ctx, [
             %{question: "When did the heron first come up?", sources: ["bookmark/1"]},
             %{question: "What did we decide about the weir?"}
           ]) =~ "Dispatched as questions #1, #2."

    assert [
             %{number: 2, status: "open", asked_by: "resident"},
             %{number: 1, sources: ["bookmark/1"]}
           ] =
             Seshat.oracles(ctx.id, [])

    assert [%{number: 1}] = Seshat.oracles(ctx.id, source: "bookmark/1")
    assert [%{number: 2}] = Seshat.oracles(ctx.id, q: "weir")

    assert Tools.run("oracle_list", ~s({"source":"bookmark/1"}), ctx.turn) =~
             "#1 [open] When did the heron first come up?"
  end

  test "a batch past the bound is refused, and an unnamed question is no question", ctx do
    bound = Oneiroi.Config.fetch!(:brain, :oracle_batch)
    many = for n <- 1..(bound + 1), do: %{question: "question #{n}"}
    assert ask(ctx, many) =~ "at most #{bound} questions a dispatch"
    assert ask(ctx, [%{question: "  "}]) =~ "Not done"
    assert Seshat.oracles(ctx.id, []) == []
  end

  test "it is her with every read: it reads her memory, refuses a write in words, answers under oracle/, and the conversation is told",
       ctx do
    ask(ctx, [%{question: "When did the heron first come up?", sources: ["bookmark/1"]}])
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:asked, messages})

        if Enum.any?(messages, &(&1[:role] == :tool)) do
          {:ok,
           "At dawn, by the weir: bookmark #1.\nNot asked: whether it mattered to you then.\nUsed: bookmark/1\nConfidence: high, it is in the bookmark itself."}
        else
          {:calls,
           [
             %{name: "bookmark_open", arguments: %{number: 1}},
             %{name: "bookmark_add", arguments: %{line: "a new one", summary: "s"}}
           ]}
        end
      end,
      for: ctx.id
    )

    assert :ok = Oracle.run(ctx.id, 1)

    # Her assembly: the prefix and her memory, the question, the source.
    assert_received {:asked, first}
    system = first |> Enum.filter(&(&1.role == :system)) |> Enum.map_join("\n", & &1.content)
    assert system =~ "# Where things stand"
    assert List.last(first).content =~ "The question: When did the heron first come up?"
    assert List.last(first).content =~ "## Source: bookmark/1"
    assert List.last(first).content =~ "You have up to 24 rounds of tool calls"

    # The read ran; the write was refused, and nothing was written.
    assert_received {:asked, second}
    answers = second |> Enum.filter(&(&1[:role] == :tool)) |> Enum.map(& &1.content)
    assert Enum.any?(answers, &(&1 =~ "the heron by the weir"))
    assert Enum.any?(answers, &(&1 =~ "the oracle reads; it writes nothing but its answer"))
    assert [%{number: 1}] = Kumbukumbu.bookmarks(ctx.id)

    assert [%{status: "answered", path: path, confidence: confidence, model: "fake/model"}] =
             Seshat.oracles(ctx.id, [])

    assert path =~ ~r/\Aoracle\/1-when-did-the-heron-first-come\.md\z/
    assert confidence == "high, it is in the bookmark itself."
    assert {:ok, %{content: content}} = Seshat.read(ctx.id, path)
    assert content =~ "# When did the heron first come up?"
    assert content =~ "asked by the resident"
    assert content =~ "Not asked: whether it mattered to you then."
    refute content =~ "the reading did not say what its question left out"
    assert content =~ "Sources: bookmark/1. Confidence: high"

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.from_name == "the oracle" and &1.text =~ "answered: #{path}")
           )

    # Read and used, as retrieval keeps them: searchable by either, and
    # counted on the asking conversation through `oracle`.
    assert [%{read: read, used: ["bookmark/1"]}] = Seshat.oracles(ctx.id, used: "bookmark/1")
    assert "bookmark/1" in read
    assert [%{number: 1}] = Seshat.oracles(ctx.id, read: "bookmark/1")
    listed = Tools.run("oracle_list", ~s({"used":"bookmark/1"}), ctx.turn)
    assert listed =~ "read by fake/model"
    assert listed =~ ~r/asked by the resident from [^,]+,/
    assert [] = Seshat.oracles(ctx.id, used: "bookmark/9")

    assert [%{target: "bookmark/1", returned: returned, used: used}] =
             Kumbukumbu.retrieval({:resident, ctx.id}, target: "bookmark/1")

    assert returned >= 1 and used >= 1

    # Run again: settled, so nothing moves.
    assert :ok = Oracle.run(ctx.id, 1)
    assert [%{status: "answered"}] = Seshat.oracles(ctx.id, [])
  end

  test "a long source is read in parts first, each by her with the question, and the answer reads the notes",
       ctx do
    long = String.duplicate("the weir in winter. ", 4_500)
    {:ok, _} = Seshat.write(ctx.id, "design/weir-notes.md", long, ctx.brain)

    ask(ctx, [
      %{question: "What happens at the weir in winter?", sources: ["design/weir-notes.md"]}
    ])

    test = self()

    Fake.script(
      fn %{messages: messages} ->
        last = List.last(messages).content

        if last =~ "You are reading part" do
          send(test, :part)
          {:ok, "It freezes, the notes say."}
        else
          send(test, {:answer, last})
          {:ok, "It freezes.\nConfidence: medium, from the notes."}
        end
      end,
      for: ctx.id
    )

    assert :ok = Oracle.run(ctx.id, 1)

    parts =
      String.length(long)
      |> Kernel./(Oneiroi.Config.fetch!(:brain, :oracle_chunk_chars))
      |> ceil()

    for _ <- 1..parts, do: assert_received(:part)
    refute_received :part
    assert_received {:answer, answer}
    assert answer =~ "read in parts first" and answer =~ "It freezes, the notes say."

    assert [%{status: "answered", confidence: "medium, from the notes."}] =
             Seshat.oracles(ctx.id, [])
  end

  # Lily's letter #21: two heavier questions came back brain_oracle_silent,
  # the reading having spent its tool rounds and written no words.
  test "a reading that spends every tool round is asked for its answer from what it read (brain #50)",
       ctx do
    ask(ctx, [%{question: "Everything about the heron?"}])
    test = self()

    Fake.script(
      fn request ->
        if request.tool_choice == "none" do
          send(test, {:last_word, request.messages})
          {:ok, "Dawn, by the weir.\nUsed: bookmark/1\nConfidence: medium, read until the bound."}
        else
          {:calls, [%{name: "bookmark_open", arguments: %{number: 1}}]}
        end
      end,
      for: ctx.id
    )

    assert :ok = Oracle.run(ctx.id, 1)
    assert_received {:last_word, messages}
    assert List.last(messages).content =~ "You have used every round of tool calls"
    # The last round's calls were run before it was asked.
    assert List.last(Enum.filter(messages, &(&1[:role] == :tool))).content =~ "the heron"

    rounds = Oneiroi.Config.fetch!(:brain, :oracle_tool_rounds)
    assert rounds > Oneiroi.Config.fetch!(:brain, :tool_rounds)
    assert length(Enum.filter(messages, &(&1[:role] == :tool))) == rounds + 1

    # The running count (brain #51): each round's results say where she is.
    tools = messages |> Enum.filter(&(&1[:role] == :tool)) |> Enum.map(& &1.content)
    assert hd(tools) =~ "(Tool round 1 of #{rounds} this turn; #{rounds - 1} left."
    assert Enum.at(tools, rounds - 1) =~ "(Tool round #{rounds} of #{rounds} this turn; 0 left."
    # The spent round's calls carry no count: the ask that follows says it.
    refute List.last(tools) =~ "(Tool round"

    assert [%{status: "answered", confidence: "medium" <> _}] = Seshat.oracles(ctx.id, [])
  end

  test "a reading that still says nothing fails with a diagnosis, not one word", ctx do
    ask(ctx, [%{question: "Anything at all?"}])

    Fake.script(
      fn request ->
        if request.tool_choice == "none",
          do: {:ok, ""},
          else: {:calls, [%{name: "bookmark_open", arguments: %{number: 1}}]}
      end,
      for: ctx.id
    )

    assert :ok = Oracle.run(ctx.id, 1)
    assert [%{status: "failed", reason: reason}] = Seshat.oracles(ctx.id, [])
    assert reason =~ "the oracle's reading answered no words (ended: "
    assert reason =~ "tool_calls: "
    assert reason =~ "ask the question again"

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.from_name == "the oracle" and &1.text =~ "answered no words (ended: ")
           )
  end

  test "a reading that fails is recorded as failed, and the conversation is told so", ctx do
    ask(ctx, [%{question: "Anything?"}])
    Fake.fail(:transport, for: ctx.id)
    assert :ok = Oracle.run(ctx.id, 1)
    assert [%{status: "failed", reason: reason}] = Seshat.oracles(ctx.id, [])
    assert is_binary(reason)

    assert Enum.any?(
             Kumbukumbu.letters(ctx.id),
             &(&1.from_name == "the oracle" and &1.text =~ "could not be answered")
           )
  end
end
