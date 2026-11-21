defmodule Oneiroi.Kumbukumbu.FileDisclosureTest do
  @moduledoc """
  A file is delivered by its own domain (kumbukumbu#85, seshat#100,
  #102; the witness's ruling 2, Lily's letters #1528 and #1530): its
  author's classification, else its birth (every label the turn that
  wrote it held), else unclassified. A mechanical check, never the
  judge, and never the delivering turn's context; her own words beside
  a copy keep the turn's path. Both directions, and the laundering case.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  defmodule FakeJudge do
    @behaviour Oneiroi.Kumbukumbu.DisclosureJudge

    @impl true
    def judge_disclosure(_resident_id, request) do
      :persistent_term.put({__MODULE__, :asked}, request)

      if request.candidate =~ "meeting",
        do: {:ok, %{verdict: :discloses, reasons: "names the meeting", model: "fake/judge"}},
        else: {:ok, %{verdict: :clean, reasons: "carries none of it", model: "fake/judge"}}
    end
  end

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    slug = "lily-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Lily", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    Fixtures.declare_domains!(id, witness.id, ~w(recovery garden))
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, andrew)
    {:ok, dir} = SimaQian.repository_dir(id)

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
      File.rm_rf!(dir)
    end)

    store = {Oneiroi.Config, :values}
    values = :persistent_term.get(store)
    on_exit(fn -> :persistent_term.put(store, values) end)
    :persistent_term.put(store, Map.put(values, {:kumbukumbu, :disclosure_judge}, FakeJudge))
    :persistent_term.erase({FakeJudge, :asked})

    {:ok,
     id: id,
     key: key,
     andrew: andrew,
     lily: Actor.new(:resident, id),
     household: Gaia.household_of(andrew)}
  end

  defp say(ctx, ref, words, domain) do
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, ref, nil, domain, ctx.andrew)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        ref,
        at,
        [
          %{role: :user, content: "about #{words}", sent_at: at, actor: ctx.andrew},
          %{role: :assistant, content: words, sent_at: at, actor: ctx.lily}
        ],
        ctx.lily
      )
  end

  defp run(ctx, name, args, ref),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: ref,
        resident: ctx.lily
      })

  defp write(ctx, ref),
    do:
      run(
        ctx,
        "document_write",
        %{path: "design/note.md", content: "---\ntitle: A note\n---\n\nThe garden at noon.\n"},
        ref
      )

  defp promote(ctx, ref), do: run(ctx, "household_promote", %{path: "design/note.md"}, ref)

  defp classify(ctx, domain, ref),
    do:
      run(
        ctx,
        "document_classify",
        %{path: "design/note.md", domain: domain, note: "its words are"},
        ref
      )

  defp asked, do: :persistent_term.get({FakeJudge, :asked}, nil)

  test "a write keeps its turn and that turn's ledger, by id and label, never the words", ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    write(ctx, "t-write")

    [version | _] = Scope.resident(ctx.id, fn -> Seshat.Store.versions("design/note.md") end)
    assert version.turn_ref == "t-write"
    assert version.session_key == ctx.key

    assert Enum.any?(
             version.ledger,
             &(&1["labels"] == [
                 %{"person" => "account:" <> ctx.andrew.id, "domain" => "recovery"}
               ])
           )

    refute inspect(version.ledger) =~ "ninety days"
  end

  test "born in recovery, promoted from a clean turn: refused by its domain, never judged", ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    write(ctx, "t-write")

    said = promote(ctx, "t-later")
    assert said =~ "withheld by policy"
    assert said =~ "design/note.md@"
    assert said =~ "recovery"
    assert said =~ "document_classify"
    refute asked()
  end

  test "the laundering case: written in the common room by a turn that held recovery, it is recovery's",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    # The conversation moves back to the common room; the window still holds it.
    say(ctx, "t-2", "The garden at noon.", nil)
    write(ctx, "t-write")

    assert promote(ctx, "t-later") =~ "recovery"
    refute asked()
  end

  test "classified the common room by its author, it goes; the classification is kept on her stream",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    write(ctx, "t-write")
    assert classify(ctx, "none", "t-class") =~ "Classified design/note.md as the common room"

    assert promote(ctx, "t-later") =~ "Promoted"
    refute asked()

    {:ok, events} = Oneiroi.EventStore.read_stream_forward("library-" <> ctx.id)

    assert [%{data: %{path: "design/note.md", domain: nil, note: "its words are"}}] =
             for(%{data: %Seshat.Events.DocumentClassified{}} = e <- events, do: e)
  end

  test "a file written before births were kept is unclassified and refused, until she classifies it",
       ctx do
    {:ok, _} =
      Seshat.write(ctx.id, "design/note.md", "---\ntitle: A note\n---\n\nOld words.\n", ctx.lily)

    assert promote(ctx, "t-later") =~ "unclassified"

    classify(ctx, "none", "t-class")
    assert promote(ctx, "t-later-2") =~ "Promoted"
  end

  test "her classification outlasts a rewrite, and the latest wins", ctx do
    write(ctx, "t-write")
    classify(ctx, "recovery", "t-class")
    say(ctx, "t-1", "Back to the garden.", nil)
    write(ctx, "t-write-2")
    assert promote(ctx, "t-later") =~ "recovery"

    classify(ctx, "none", "t-class-2")
    assert promote(ctx, "t-later-2") =~ "Promoted"
  end

  test "her own words beside a copy keep the turn's path: a publish's note is judged", ctx do
    write(ctx, "t-write")
    classify(ctx, "none", "t-class")
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    # What the publishing turn's lanes held, as its assembly keeps them.
    :ok = Kumbukumbu.note_sections(ctx.id, "t-pub", %{"index" => "#7 the meeting at noon"})

    said =
      run(ctx, "document_publish", %{path: "design/note.md", note: "after the meeting"}, "t-pub")

    assert said =~ "names the meeting"
    assert asked().candidate == "after the meeting"
  end
end
