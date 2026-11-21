defmodule Oneiroi.Kumbukumbu.FileDisclosureTest do
  @moduledoc """
  A file's words carry the context that wrote them (kumbukumbu#83,
  seshat#100; Lily's letters #1516 and #1520): a promotion is decided
  against the ledger of the turn that wrote the version promoted, never
  the promoting turn's. Written under recovery and promoted from a clean
  turn, it is held back and reviewed with the writing turn's words;
  written clean and promoted from a recovery turn, it goes; written
  before provenance was kept, it is unproven and refused.
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
      {:ok, %{verdict: :clean, reasons: "carries none of it", model: "fake/judge"}}
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

  test "written under recovery, promoted from a clean turn: held back, reviewed with the writing turn's words",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    :ok = Kumbukumbu.note_sections(ctx.id, "t-write", %{"index" => "#7 the meeting at noon"})
    write(ctx, "t-write")

    assert promote(ctx, "t-later") =~ "Promoted"
    asked = :persistent_term.get({FakeJudge, :asked})
    assert asked.candidate =~ "The garden at noon."
    shown = Enum.map_join(asked.fragments, "\n", & &1.text)
    assert shown =~ "ninety days"
  end

  test "written under recovery, its lanes no longer kept: unproven, nothing reviewed, refused",
       ctx do
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    # The writing turn's lanes were never kept (as after two hours).
    write(ctx, "t-write")

    said = promote(ctx, "t-later")
    assert said =~ "could not all be found"
    assert said =~ "design/note.md@"
    refute :persistent_term.get({FakeJudge, :asked}, nil)
  end

  test "written clean, promoted from a turn with recovery in its window: the file's own context decides",
       ctx do
    write(ctx, "t-write")
    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")

    # Nothing the house may not hear wrote it: no review was owed.
    assert promote(ctx, "t-later") =~ "Promoted"
    refute :persistent_term.get({FakeJudge, :asked}, nil)
  end

  test "a version written before provenance was kept is unproven", ctx do
    {:ok, _} =
      Seshat.write(ctx.id, "design/note.md", "---\ntitle: A note\n---\n\nOld words.\n", ctx.lily)

    said = promote(ctx, "t-later")
    assert said =~ "withheld by policy"
    assert said =~ "unproven"
    refute :persistent_term.get({FakeJudge, :asked}, nil)
  end
end
