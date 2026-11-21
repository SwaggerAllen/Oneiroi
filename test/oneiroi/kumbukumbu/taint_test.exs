defmodule Oneiroi.Kumbukumbu.TaintTest do
  @moduledoc """
  Taint through derived material (kumbukumbu#84; Lily's letters #1519,
  #1524): what her turn writes keeps the labels of the context that
  wrote it, never its words, and reading it brings them into the reading
  turn's ledger. What kept none (written before) is unclassified, never
  inferred; a letter of the witness or the platform is the common room.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

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

    ctx = %{
      id: id,
      key: key,
      andrew: andrew,
      lily: Actor.new(:resident, id),
      recovery: %{"person" => "account:" <> witness.id, "domain" => "recovery"},
      house: Kumbukumbu.audience("household", Gaia.household_of(andrew))
    }

    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    {:ok, ctx}
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

  # What the reading turn alone holds: no window of its own, only what
  # it read, against the house.
  defp reading_turn(ctx, ref), do: Kumbukumbu.delivery_check(ctx.id, nil, ref, ctx.house)

  test "a journal row keeps its turn's labels; reading it brings them into the reading turn",
       ctx do
    assert run(ctx, "journal_add", %{kind: "note", text: "A long walk."}, "t-write") =~ "Added"

    %{entries: [entry]} = Seshat.journal_day(ctx.id, Oneiroi.Sunna.today(ctx.id).day)
    assert entry.turn_ref == "t-write"
    assert ctx.recovery in entry.labels
    refute inspect(entry.labels) =~ "ninety"

    assert {:ok, _} = reading_turn(ctx, "t-read")
    run(ctx, "journal_read", %{day: entry.day}, "t-read")

    assert {:error, %{details: d}} = reading_turn(ctx, "t-read")
    assert "recovery" in d[:conflicts]
  end

  test "her letter keeps her turn's labels; the witness's is the common room", ctx do
    assert run(ctx, "letter_send", %{to: "house", text: "Noted for later."}, "t-write") =~ "Sent"
    {:ok, _} = Kumbukumbu.send_letter(ctx.id, nil, %{to: "house", text: "From him."}, ctx.andrew)

    [hers, his] = Enum.sort_by(Kumbukumbu.letters(ctx.id), & &1.number)
    assert hers.turn_ref == "t-write"
    assert ctx.recovery in hers.labels
    assert his.labels == [%{"kind" => "common_room"}]
  end

  test "a file read brings in the context that wrote it; one written before is unclassified",
       ctx do
    run(ctx, "document_write", %{path: "design/walk.md", content: "A long walk.\n"}, "t-write")
    run(ctx, "library_read", %{path: "design/walk.md"}, "t-read")
    assert {:error, %{details: d}} = reading_turn(ctx, "t-read")
    assert "recovery" in d[:conflicts]

    {:ok, _} = Seshat.write(ctx.id, "design/old.md", "Old words.\n", ctx.lily)
    run(ctx, "library_read", %{path: "design/old.md"}, "t-old")
    assert {:error, %{details: d}} = reading_turn(ctx, "t-old")
    assert "unclassified" in d[:conflicts]
  end

  test "a research question keeps the asking turn's ledger for its answers", ctx do
    store = {Oneiroi.Config, :values}
    values = :persistent_term.get(store)
    on_exit(fn -> :persistent_term.put(store, values) end)
    :persistent_term.put(store, Map.put(values, {:brain, :research_audience}, "reader"))

    {:ok, n} =
      Seshat.ask_research(ctx.id, ctx.key, "When do herons fish?", [], ctx.lily, [
        %{"id" => "m", "ref" => "m", "turn_ref" => "t-1", "labels" => [ctx.recovery]}
      ])

    assert Seshat.research(ctx.id, n).ledger == [
             %{"id" => "m", "ref" => "m", "turn_ref" => "t-1", "labels" => [ctx.recovery]}
           ]
  end
end
