defmodule Oneiroi.Brain.DomainReviewTest do
  @moduledoc """
  kumbukumbu#110 (the witness, 2026-11-25: "We need to be able to retag
  things that have undeclared domains and unclassified memories via tool
  call"): `domain_review` lists the undeclared domains her messages are
  in and the records still unclassified; `domain_recategorize` moves an
  undeclared domain whole, never a declared one; `record_classify` sets a
  record's domain, which the labels pass never derives again.
  """
  use Oneiroi.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.LabelPropagation
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Store.Message
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.Seshat

  setup do
    witness = Fixtures.account!()
    resident = Fixtures.resident!(witness)
    Fixtures.declare_domains!(resident.id, witness.id, ~w(recovery))
    andrew = Actor.new(:witness, witness.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, witness.id, andrew)
    {:ok, dir} = Oneiroi.SimaQian.repository_dir(resident.id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok,
     id: resident.id,
     key: key,
     andrew: andrew,
     brain: brain,
     lily: Actor.new(:resident, resident.id),
     day: Oneiroi.Sunna.today(resident.id).day,
     his: "account:" <> witness.id}
  end

  defp run(ctx, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t-now",
        resident: ctx.lily
      })

  defp turn!(ctx, ref, words) do
    at = Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        ref,
        at,
        [
          %{role: :user, content: words, sent_at: at, actor: ctx.andrew},
          %{role: :assistant, content: "Noted.", sent_at: at, actor: ctx.brain}
        ],
        ctx.brain
      )
  end

  # A domain named before the agreement declared its domains: written
  # past the tag's own check, as the 11-14 backfill's were.
  defp undeclared!(ctx, ref, tagged) do
    Scope.platform(fn ->
      Repo.update_all(
        from(m in Message, where: m.resident_id == ^ctx.id and m.turn_ref == ^ref),
        set: [domain: "business", domain_person: ctx.his, domain_tagged: tagged]
      )
    end)
  end

  defp domains_of(ctx) do
    Scope.resident(ctx.id, fn ->
      Repo.all(
        from(m in Message,
          where: m.session_key == ^ctx.key and m.role != "tool",
          order_by: [asc: m.turn_ref],
          distinct: m.turn_ref,
          select: {m.turn_ref, m.domain}
        )
      )
    end)
  end

  test "an undeclared domain is listed and moved whole; a declared one never is", ctx do
    turn!(ctx, "t-1", "The quarterly numbers.")
    turn!(ctx, "t-2", "And the hiring plan.")
    undeclared!(ctx, "t-1", true)
    undeclared!(ctx, "t-2", false)

    review = run(ctx, "domain_review", %{which: "domains"})
    assert review =~ ~r/- business \(the witness's life\): \d+ messages in 1 conversations/
    assert review =~ "first named at turn t-1 in #{ctx.key}"

    assert run(ctx, "domain_recategorize", %{from: "recovery", to: "none"}) =~
             "No message of yours is in an undeclared domain"

    assert run(ctx, "domain_recategorize", %{from: "business", to: "golf"}) =~ "not declared"

    assert run(ctx, "domain_recategorize", %{
             from: "business",
             to: "recovery",
             note: "the numbers were his program's"
           }) =~ "everything in business is now in recovery"

    assert domains_of(ctx) == [{"t-1", "recovery"}, {"t-2", "recovery"}]
    assert run(ctx, "domain_review", %{which: "domains"}) =~ "Undeclared domains: none"

    # A declared domain moves by agreement, never wholesale.
    assert {:error, %{kind: :kumbukumbu_domain_declared}} =
             Kumbukumbu.recategorize_domain(
               ctx.id,
               {ctx.his, "recovery"},
               {nil, nil},
               "no",
               ctx.lily
             )
  end

  test "an unclassified record is listed, classified by her, and the labels pass leaves it",
       ctx do
    # Written before labels were kept: no turn, nothing kept.
    {:ok, _} = Seshat.journal_add(ctx.id, ctx.day, "note", "Long day.", ctx.brain)
    [row] = Seshat.journal_day(ctx.id, ctx.day).entries
    id = "#{ctx.day}/#{row.number}"

    assert run(ctx, "domain_review", %{which: "records"}) =~ "- journal #{id} ("
    assert run(ctx, "domain_review", %{which: "records"}) =~ "unclassified"

    assert run(ctx, "record_classify", %{kind: "journal", id: "#{ctx.day}/99", domain: "none"}) =~
             "No journal row"

    assert run(ctx, "record_classify", %{kind: "journal", id: id, domain: "business"}) =~
             "not declared"

    assert run(ctx, "record_classify", %{
             kind: "journal",
             id: id,
             domain: "recovery",
             note: "the program's day"
           }) =~ "Classified journal #{id} as recovery"

    assert run(ctx, "domain_review", %{which: "records"}) =~ "Records: none"

    # The pass reads the day again and leaves her classification standing.
    assert {:ok, _} = LabelPropagation.run(ctx.id, ctx.day, ctx.day)

    assert %{^id => [%{"person" => person, "domain" => "recovery"}]} =
             Kumbukumbu.derived_labels(ctx.id, "journal", [id])

    assert person == ctx.his
  end
end
