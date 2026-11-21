defmodule Oneiroi.Kumbukumbu.DeclaredDomainsTest do
  @moduledoc """
  A domain is named only once the agreement declares it (the witness's
  ruling, 2026-11-21; agathos-daimon#57, kumbukumbu#90; Lily's letter
  #1564): a tag, a classification, an annotation and a backfill's lists
  naming one it does not are refused, naming what is declared; the
  common room always passes; a domain declared by a wall counts.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.SimaQian

  setup do
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    slug = "lily-#{System.unique_integer([:positive])}"
    {:ok, id} = AgathosDaimon.create("Lily", slug, witness.id, andrew)
    Fixtures.agreed!(id, witness.id)
    Fixtures.declare_domains!(id, witness.id, ~w(recovery))
    {:ok, key} = Kumbukumbu.main_session(id, witness.id, andrew)
    {:ok, dir} = SimaQian.repository_dir(id)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, id: id, key: key, andrew: andrew, lily: Actor.new(:resident, id), witness: witness}
  end

  defp run(ctx, name, args),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t-now",
        resident: ctx.lily
      })

  test "a tag names only a declared domain, naming what is; the common room always", ctx do
    assert {:error, %{kind: :kumbukumbu_domain_undeclared, details: d}} =
             Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-1", nil, "business", ctx.andrew)

    assert "recovery" in d[:declared]
    assert run(ctx, "domain_tag", %{domain: "business"}) =~ "not declared"
    assert run(ctx, "domain_tag", %{domain: "recovery"}) =~ "Tagged"
    assert run(ctx, "domain_tag", %{domain: "none"}) =~ "Tagged"
  end

  test "a classification and an annotation name only declared domains", ctx do
    run(ctx, "document_write", %{path: "design/note.md", content: "A note.\n"})

    assert run(ctx, "document_classify", %{path: "design/note.md", domain: "business"}) =~
             "declared"

    assert run(ctx, "document_classify", %{path: "design/note.md", domain: "recovery"}) =~
             "Classified"

    :ok =
      AgathosDaimon.write_file(
        ctx.id,
        "SOUL.md",
        "# SOUL\n\nI keep one person company.\n",
        %{},
        ctx.andrew
      )

    [%{number: n} | _] = AgathosDaimon.soul_lines(ctx.id)

    assert run(ctx, "soul_annotate", %{number: n, domains: [%{domain: "business"}]}) =~
             "declared"

    assert run(ctx, "soul_annotate", %{number: n, domains: [%{domain: "recovery"}]}) =~
             "Annotated"
  end

  test "a backfill's lists name only declared domains", ctx do
    day = Oneiroi.Sunna.today(ctx.id).day |> Date.from_iso8601!() |> Date.add(-2)
    day = Date.to_iso8601(day)

    assert {:error, %{site: :sunna_backfill_start_undeclared}} =
             Oneiroi.Sunna.backfill_start(ctx.id, day, day, %{"his" => ["business"]}, ctx.andrew)

    assert {:ok, 1} =
             Oneiroi.Sunna.backfill_start(ctx.id, day, day, %{"his" => ["recovery"]}, ctx.andrew)

    Oneiroi.Sunna.backfill_stop(ctx.id)
  end

  test "a domain a wall names is declared too", ctx do
    {:ok, v} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{
          "domain_walls" => [
            %{
              "memory" => %{"person" => "account:" <> ctx.witness.id, "domain" => "family"},
              "context" => %{"person" => "*", "domain" => "*"}
            }
          ]
        },
        "",
        "a wall",
        ctx.andrew
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, v, "agreed", ctx.lily)
    assert :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, "t-1", nil, "family", ctx.andrew)
  end
end
