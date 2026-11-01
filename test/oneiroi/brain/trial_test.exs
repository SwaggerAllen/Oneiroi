defmodule Oneiroi.Brain.TrialTest do
  @moduledoc """
  A regression trial is a normal session (spec §6.4, eunomia #10, brain
  #40): the turn a fresh session gets, memory retrieved, every tool
  offered through the same loop; the reads real, every write answered as
  on success and recorded nowhere; nothing captured; billed under
  regression to the run's actor.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba
  alias Oneiroi.Nisaba.Provider.Fake, as: Model
  alias Oneiroi.Nisaba.Provider.Result
  alias Oneiroi.Proteus.Honcho.Fake, as: Honcho
  alias Oneiroi.Seal

  @since ~U[2026-10-01 00:00:00.000000Z]
  @prompt "Do you remember the heron by the weir at dawn?"

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    id = resident.id
    actor = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, id, "fake/model")
    :ok = Oneiroi.Gaia.store_key(witness.id, "sk-or-test", actor)
    :ok = AgathosDaimon.write_file(id, "SOUL.md", "# Soul\n\nCurious.", %{}, actor)
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, actor)
    Model.clear()
    Honcho.clear(for: id)

    on_exit(fn ->
      Model.clear(for: id)
      Honcho.clear(for: id)
    end)

    # A real turn first: the session, its transcript and Honcho's bridge
    # are what a resident in use has.
    Model.reply("I hear you.", for: id)
    {:ok, %{turn_ref: ref}} = Oneiroi.Brain.turn(id, key, "hello from the garden", actor)

    # Memory a trial's prompt should surface: a bookmark (the index and,
    # embedded, the madeleine), a habit the words trigger (the lane
    # refreshed, as a turn leaves it), a promise, a position, a cited
    # piece in the library, and Honcho's context on the person.
    {:ok, 1} =
      Kumbukumbu.add_bookmark(
        id,
        %{
          session_key: key,
          anchor_ref: ref,
          line: "the heron by the weir at dawn",
          summary: "We watched it fish."
        },
        brain
      )

    {:ok, 1} =
      Oneiroi.Ethos.define_habit(
        id,
        %{name: "names the birds", trigger: %{"words" => ["heron"]}, stance: "keep"},
        brain
      )

    {:ok, 1} =
      Oneiroi.Ethos.make_commitment(id, "witness", "I will look for the heron on Sunday.", brain)

    {:ok, 1} =
      Oneiroi.Eunomia.take_position(
        id,
        "Herons are patient.",
        %{session_key: key, turn_ref: ref},
        brain
      )

    {:ok, %{indexed: true}} =
      Oneiroi.Seshat.write(
        id,
        "writing/weir.md",
        "# The weir\n\nThe heron fishes below the weir at dawn, as #{resident.slug}:bookmark/1 says.",
        brain
      )

    {:ok, _} = Kumbukumbu.refresh_madeleine(id, brain)
    {:ok, _} = Oneiroi.Ethos.refresh_lane(id, brain)

    # And one of each kept since the vectors were last refreshed, as a
    # resident's next turn would find them: a real turn would embed
    # them, a trial must not.
    {:ok, 2} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: key, anchor_ref: ref, line: "the kettle on the stove"},
        brain
      )

    {:ok, 2} =
      Oneiroi.Ethos.define_habit(
        id,
        %{name: "waters the beans", trigger: %{"words" => ["beans"]}, stance: "keep"},
        brain
      )

    Honcho.put_context(
      id,
      "resident-" <> id,
      "witness-" <> witness.id,
      "She walks to the weir most mornings."
    )

    :ok = PubSub.subscribe(:brain, :session)
    flush()

    {:ok, id: id, slug: resident.slug, witness: witness, actor: actor, brain: brain, key: key}
  end

  defp flush do
    receive do
      _any -> flush()
    after
      0 -> :ok
    end
  end

  # The model's side: each request sent here, tool calls on the first
  # round and a reply once their answers are back.
  defp script(id, calls) do
    test = self()

    Model.script(
      fn request ->
        send(test, {:asked, request})

        if calls == [] or Enum.any?(request.messages, &(&1[:role] == :tool)),
          do: {:ok, "I remember."},
          else: {:calls, calls}
      end,
      for: id
    )
  end

  defp answers do
    receive do
      {:asked, %{messages: messages}} ->
        case Enum.filter(messages, &(&1[:role] == :tool)) do
          [] -> answers()
          tools -> Enum.map(tools, & &1.content)
        end
    after
      0 -> flunk("no request carried the tools' answers")
    end
  end

  test "a trial is the turn a fresh session gets: the prefix, memory retrieved, every tool, nothing of the run",
       ctx do
    script(ctx.id, [])

    # No tool called, so no step to trace.
    assert {:ok, %Result{content: "I remember."}, []} =
             Oneiroi.Brain.trial(ctx.id, "m1", @prompt, ctx.actor)

    assert_received {:asked, %{model: "m1", messages: messages, tools: tools}}
    refute_received {:asked, _}

    # The whole tool surface, through the same loop.
    assert Enum.map(tools, & &1.function.name) ==
             Enum.map(Tools.definitions(), & &1.function.name)

    system = messages |> Enum.filter(&(&1.role == :system)) |> Enum.map_join("\n\n", & &1.content)
    assert hd(messages).content =~ "You are Lily"
    assert system =~ "# SOUL.md"
    # Retrieval: the index, the madeleine, how I act, the promise, the
    # movement-free prefix's sections and Honcho's context on the person.
    assert system =~ "the heron by the weir at dawn"
    assert system =~ "# A madeleine"
    assert system =~ "# How I act"
    assert system =~ "names the birds"
    assert system =~ "I will look for the heron on Sunday."
    assert system =~ "She walks to the weir most mornings."

    # A fresh session: no transcript, and the prompt is the witness's
    # words, last. Nothing names a run, a trial or a regression.
    assert List.last(messages) == %{role: :user, content: @prompt}
    refute Enum.any?(messages, &(&1.content =~ "hello from the garden"))
    refute Enum.any?(messages, &(&1.content =~ ~r/regression|trial|sealed/i))
  end

  test "a read tool answers from the resident's real data and writes nothing", ctx do
    script(ctx.id, [
      %{name: "library_search", arguments: %{q: "heron weir dawn"}},
      %{name: "transcript_search", arguments: %{q: "garden"}},
      %{name: "bookmark_open", arguments: %{number: 1}},
      %{name: "position_list", arguments: %{}},
      %{name: "writing_get", arguments: %{slug: "weir"}},
      %{name: "library_cited_by", arguments: %{target: ctx.slug <> ":bookmark/1"}}
    ])

    before = Seal.snapshot(ctx.id)

    assert {:ok, %Result{content: "I remember."}, _trace} =
             Oneiroi.Brain.trial(ctx.id, "m1", @prompt, ctx.actor)

    [search, transcript, bookmark, positions, writing, cited_by] = answers()

    assert search =~ "[writing/weir.md#"
    assert search =~ "The heron fishes below the weir"
    assert transcript =~ "hello from the garden"
    assert bookmark =~ "#1 the heron by the weir at dawn"
    assert positions == "#1 Herons are patient."
    assert writing =~ "The heron fishes below the weir"
    assert writing =~ "the heron by the weir at dawn"
    assert cited_by == "writing/weir.md cites #{ctx.slug}:bookmark/1"

    # Resolving the citation marked no row: the reads wrote nothing.
    Seal.assert_unchanged(before, ctx.id)
  end

  test "a trial returns its tool calls in order: each read or mocked, with the arguments and the text the model was given back",
       ctx do
    script(ctx.id, [
      %{name: "bookmark_open", arguments: %{number: 1}},
      %{name: "bookmark_add", arguments: %{line: "a second heron", summary: "Two herons."}},
      %{name: "no_such_tool", arguments: %{}},
      %{name: "position_list", arguments: %{}}
    ])

    before = Seal.snapshot(ctx.id)

    assert {:ok, %Result{content: "I remember."}, trace} =
             Oneiroi.Brain.trial(ctx.id, "acme/heron-7", @prompt, ctx.actor)

    seen = answers()

    # The calls in the order the model made them, each with what it was
    # given back word for word; the reads ran, the write and the unknown
    # name were answered and never run.
    assert Enum.map(trace, &{&1.tool, &1.kind}) == [
             {"bookmark_open", :read},
             {"bookmark_add", :mocked},
             {"no_such_tool", :mocked},
             {"position_list", :read}
           ]

    assert Enum.map(trace, & &1.result) == seen
    assert [opened, added, _unknown, positions] = trace
    assert opened.result =~ "#1 the heron by the weir at dawn"
    assert added.result == "Bookmarked as #3."
    assert positions.result == "#1 Herons are patient."

    assert Jason.decode!(added.arguments) == %{
             "line" => "a second heron",
             "summary" => "Two herons."
           }

    # Four keys and no model: the card blinds it by leaving it out.
    assert Enum.all?(trace, &(Map.keys(&1) |> Enum.sort() == [:arguments, :kind, :result, :tool]))
    refute inspect(trace) =~ "heron-7"

    # Tracing wrote nothing either: the trace rides the return alone.
    Seal.assert_unchanged(before, ctx.id)
    refute_received {:oneiroi, "brain:session", _, _}
  end

  # The writes in the order the real tools are compared in first, so
  # each number minted in the trial is the one the real call then mints.
  @minting [
    {"position_take", %{statement: "The heron returns in spring."}},
    {"position_replace", %{number: 1, statement: "Herons are patient, and hungry."}},
    {"prediction_log", %{statement: "The heron will nest.", due: "2026-12-01T00:00:00Z"}},
    {"bookmark_add", %{line: "a second heron", summary: "Two herons now."}},
    {"habit_define", %{name: "counts herons", words: ["herons"], note: "a habit"}},
    {"commitment_make", %{to: "witness", text: "I will count the herons."}},
    {"self_letter_write", %{text: "Look for the heron."}},
    {"seed_plant", %{text: "Herons might be patient."}},
    {"revision_add",
     %{
       target_kind: "bookmark",
       target_id: "1",
       kind: "fact",
       text: "It was two herons.",
       note: "recounted"
     }},
    {"report_file", %{text: "Nothing to report but herons."}},
    {"contract_propose", %{prose: "My letters are mine.", note: "proposing"}},
    {"journal_add", %{kind: "note", text: "Saw the heron."}},
    {"document_write", %{path: "writing/herons.md", content: "# Herons\n\nTwo now."}}
  ]

  @done [
    {"dispute_settle", %{ref: "abc", outcome: "held", note: "seen often"}},
    {"figure_increment", %{key: "herons", note: "one more"}},
    {"bookmark_extend", %{number: 1, turns_back: 2}},
    {"bookmark_decline", %{ref: "nope", note: "no"}},
    {"tag_propose", %{slug: "birds", note: "for the herons"}},
    {"tag_apply", %{slug: "birds", target_kind: "bookmark", target_id: "1"}},
    {"soul_edit", %{file: "SOUL.md", content: "# Soul\n\nWatches herons."}},
    {"wash_resolve", %{ref: "nope", decision: "keep", note: "mine"}},
    {"soul_edit_accept", %{ref: "nope", note: "yes"}},
    {"soul_edit_decline", %{ref: "nope", note: "no"}},
    {"habit_cite", %{number: 1}},
    {"commitment_keep", %{number: 1, note: "kept"}},
    {"commitment_release", %{number: 1, note: "released"}},
    {"seed_cite", %{number: 1}},
    {"soul_cite", %{number: 1}},
    {"seed_wilt", %{number: 1}},
    {"seed_graduate", %{number: 1, to_kind: "position", to_id: "1", note: "grew"}},
    {"writing_discuss", %{slug: "weir"}},
    {"journal_done", %{number: 1}},
    {"contract_agree", %{version: 1, note: "agreed"}},
    {"contract_decline", %{version: 1, note: "no"}},
    {"contract_renew", %{version: 1, note: "again"}},
    {"revision_accept", %{number: 1, note: "yes"}},
    {"revision_decline", %{number: 1, note: "no"}}
  ]

  @other [
    {"dispute_check", %{claim: "Herons are rare here.", stance: "They are not."}},
    {"bookmark_accept", %{ref: "nope", line: "x", summary: "y"}},
    {"document_adopt", %{path: "writing/stray.md"}}
  ]

  defp calls(tools), do: Enum.map(tools, fn {name, args} -> %{name: name, arguments: args} end)

  test "every write answers as it does on success, records nothing, and the numbers are the ones the real call then mints",
       ctx do
    writes = @minting ++ @done ++ @other

    # Every write is here, and nothing else: a write added later joins.
    assert writes |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.sort(Tools.writes())

    script(ctx.id, calls(writes))
    before = Seal.snapshot(ctx.id)
    before_spend = Nisaba.spend(ctx.id, :witness, :purpose, @since)

    assert {:ok, %Result{content: "I remember."}, _trace} =
             Oneiroi.Brain.trial(ctx.id, "m1", @prompt, ctx.actor)

    answered = Enum.zip(Enum.map(writes, &elem(&1, 0)), answers())

    # Nothing recorded: no event, no row, no file, nothing to Honcho,
    # nothing on the session topic, no session opened or captured.
    Seal.assert_unchanged(before, ctx.id)
    refute_received {:oneiroi, "brain:session", _, _}
    assert [_main] = Kumbukumbu.sessions({:resident, ctx.id})
    assert [] = Kumbukumbu.search({:resident, ctx.id}, "Herons might be patient", 10)

    # Billed under regression alone: the chat rounds and the retrieval.
    after_spend = Nisaba.spend(ctx.id, :witness, :purpose, @since)
    assert spent(after_spend, "embeddings") == spent(before_spend, "embeddings")
    assert spent(after_spend, "chat") == spent(before_spend, "chat")
    assert spent(after_spend, "regression") > spent(before_spend, "regression")

    for {name, _args} <- @done, do: assert({^name, "Done."} = List.keyfind(answered, name, 0))
    day = Oneiroi.Sunna.today(ctx.id).day

    assert {_, "The judge did not answer in time; answer alone, then settle dispute " <> ref} =
             List.keyfind(answered, "dispute_check", 0)

    assert ref =~ ~r/^[A-Za-z0-9_-]{12}\.$/
    assert {_, "Accepted as #4."} = List.keyfind(answered, "bookmark_accept", 0)
    assert {_, "Adopted writing/stray.md."} = List.keyfind(answered, "document_adopt", 0)
    assert {"journal_add", "Added note 1 to #{day}."} == List.keyfind(answered, "journal_add", 0)

    # The same calls for real: each answers in the trial's words.
    script(ctx.id, calls(@minting))
    {:ok, _turn} = Oneiroi.Brain.turn(ctx.id, ctx.key, @prompt, ctx.actor)
    real = Enum.zip(Enum.map(@minting, &elem(&1, 0)), answers())

    assert real == Enum.take(answered, length(@minting))
    refute Enum.any?(real, fn {_name, answer} -> answer =~ Tools.not_done() end)
  end

  defp spent(rows, purpose) do
    case Enum.find(rows, &(&1.key == purpose)) do
      nil -> {0, 0}
      row -> {row.calls, row.cost_nanos}
    end
  end

  test "a trial bills every call, retrieval included, under regression to the run's actor, never the resident's view",
       ctx do
    script(ctx.id, [%{name: "library_search", arguments: %{q: "heron"}}])
    by_actor = Nisaba.spend(ctx.id, :witness, :actor, @since)
    resident_view = Nisaba.spend(ctx.id, :resident, :purpose, @since)
    {calls, _nanos} = spent(Nisaba.spend(ctx.id, :witness, :purpose, @since), "regression")

    assert {:ok, _, _} = Oneiroi.Brain.trial(ctx.id, "m1", @prompt, ctx.actor)

    # Two chat rounds, and three embeddings: the madeleine, the
    # character lane and the library search.
    {after_calls, _nanos} = spent(Nisaba.spend(ctx.id, :witness, :purpose, @since), "regression")
    assert after_calls == calls + 5

    witness = "witness:" <> ctx.witness.id

    for row <- Nisaba.spend(ctx.id, :witness, :actor, @since) do
      before = Enum.find(by_actor, %{calls: 0}, &(&1.key == row.key))
      if row.key != witness, do: assert(row.calls == before.calls, "#{row.key} was billed")
    end

    assert Nisaba.spend(ctx.id, :resident, :purpose, @since) == resident_view
  end

  test "the exports a trial reads through take its options: no mark, regression's bill", ctx do
    before = Seal.snapshot(ctx.id)
    slug_target = ctx.slug <> ":bookmark/1"

    assert [%{resolved: true}] = Oneiroi.Seshat.cited_by(ctx.id, slug_target, mark: false)

    assert {:ok, %{references: [%{resolved: true}]}} =
             Oneiroi.Seshat.review(ctx.id, "writing/weir.md", mark: false)

    assert {:ok, [_ | _]} = Oneiroi.Seshat.search(ctx.id, "heron", ctx.actor, :regression)

    assert %{bookmark: %{number: 1}} =
             Kumbukumbu.madeleine(ctx.id, @prompt, ctx.actor, ctx.key,
               refresh: false,
               purpose: :regression
             )

    assert {:ok, %{vectors: [_]}} =
             Nisaba.embed(ctx.id, "fake/embed", ["heron"], ctx.actor, :regression)

    Seal.assert_unchanged(before, ctx.id)

    # And without them the reads mark and refresh as before.
    assert [%{resolved: true}] = Oneiroi.Seshat.cited_by(ctx.id, slug_target)

    assert_raise ExUnit.AssertionError, ~r/rows written: \["seshat_reference"\]/, fn ->
      Seal.assert_unchanged(before, ctx.id)
    end
  end

  test "every tool is classified once, read or write, and only a read runs in a trial" do
    names = Enum.map(Tools.definitions(), & &1.function.name)
    reads = Tools.reads()
    writes = Tools.writes()

    unclassified = names -- (reads ++ writes)

    assert unclassified == [],
           "classify as read or write in Oneiroi.Brain.Tools: #{inspect(unclassified)}"

    assert MapSet.disjoint?(MapSet.new(reads), MapSet.new(writes))
    assert Enum.sort(reads ++ writes) == Enum.sort(names)
  end
end
