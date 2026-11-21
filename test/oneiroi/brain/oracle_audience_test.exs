defmodule Oneiroi.Brain.OracleAudienceTest do
  @moduledoc """
  The oracle composed for an audience (kumbukumbu#87; the witness's
  ruling, 2026-11-20: "it needs to be possible to pass it an audience and
  have it soft filter on that audience"; Lily's letters #1533, #1534).
  For the house, a recovery source is withheld from the oracle's context
  and cited by its ref alone, never its domain; the answer records what
  it was composed for and carries no recovery label, so a clean turn
  reading it holds nothing the house may not hear. With no audience, it
  is hers: everything read, labelled as built.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Oracle
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Nisaba.Provider.Fake
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    :ok = Gaia.store_key(witness.id, "sk-or-test", andrew)

    {:ok, _} =
      Seshat.household_propose_contract(andrew, "We share this house.", "founding", [
        %{"setting" => "conversation", "value" => "round_robin"}
      ])

    slug = "lily-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Lily", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, andrew)
    {:ok, dir} = SimaQian.repository_dir(id)
    lily = Actor.new(:resident, id, "fake/model")
    test = self()

    Fake.script(
      fn %{messages: messages} ->
        send(test, {:asked, Enum.map_join(messages, "\n", &to_string(&1[:content]))})
        {:ok, "The garden wants water.\nUsed: none\nConfidence: medium, from memory."}
      end,
      for: id
    )

    on_exit(fn ->
      Fake.clear(for: id)
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
      File.rm_rf!(dir)
    end)

    :ok = Kumbukumbu.tag_domain(id, key, "t-rec", nil, "recovery", andrew)
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        id,
        key,
        "t-rec",
        at,
        [
          %{
            role: :assistant,
            content: "The meeting at noon, ninety days.",
            sent_at: at,
            actor: lily
          }
        ],
        lily
      )

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        id,
        %{session_key: key, anchor_ref: "t-rec", line: "the meeting", summary: "noon"},
        lily
      )

    {:ok, [1]} =
      Seshat.dispatch_oracle(
        id,
        key,
        [
          %{
            "question" => "What should the house's winter post say?",
            "sources" => ["bookmark/#{n}"]
          }
        ],
        lily
      )

    household = Gaia.household_of(andrew)

    {:ok,
     id: id,
     key: key,
     lily: lily,
     n: n,
     house: Kumbukumbu.audience("household", household),
     composed_for: %{"kind" => "household", "id" => household}}
  end

  defp asked do
    receive do
      {:asked, words} -> words <> asked()
    after
      0 -> ""
    end
  end

  defp answer_version(ctx) do
    [%{path: path}] = Seshat.oracles(ctx.id, [])
    [version | _] = Scope.resident(ctx.id, fn -> Seshat.Store.versions(path) end)
    {path, version}
  end

  test "composed for the house: the recovery source withheld, cited by ref alone, the answer house-legal",
       ctx do
    assert :ok = Oracle.run(ctx.id, 1, nil, ctx.composed_for)

    words = asked()
    refute words =~ "ninety days"
    assert words =~ "withheld"
    assert words =~ "bookmark/#{ctx.n}"
    # The withheld lines say the fact, never the domain (Lily's #1534).
    for line <- String.split(words, "\n"),
        line =~ "bookmark/#{ctx.n}" and line =~ "ithheld",
        do: refute(line =~ "recovery")

    {path, version} = answer_version(ctx)
    assert version.composed_for == "household:#{ctx.house.id}"
    refute inspect(version.ledger) =~ "recovery"

    # A turn that reads it holds nothing the house may not hear.
    Tools.run("library_read", Jason.encode!(%{path: path}), %{
      resident_id: ctx.id,
      session_key: ctx.key,
      turn_ref: "t-read",
      resident: ctx.lily
    })

    assert {:ok, _} = Kumbukumbu.delivery_check(ctx.id, nil, "t-read", ctx.house)
  end

  test "with no audience it is hers: the source read whole, its label on the answer", ctx do
    assert :ok = Oracle.run(ctx.id, 1)

    assert asked() =~ "ninety days"
    {_path, version} = answer_version(ctx)
    assert version.composed_for == nil
    assert inspect(version.ledger) =~ "recovery"
  end
end
