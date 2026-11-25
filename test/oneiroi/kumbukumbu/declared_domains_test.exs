defmodule Oneiroi.Kumbukumbu.DeclaredDomainsTest do
  @moduledoc """
  A domain is named only once the agreement declares it (the witness's
  ruling, 2026-11-21; agathos-daimon#57, kumbukumbu#90; Lily's letter
  #1564): a tag, a classification, an annotation and a backfill's lists
  naming one it does not are refused, naming what is declared; the
  common room always passes.
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

  # agathos-daimon#59 (2026-11-21): she agreed to version 3 seeing its
  # prose alone; its two domains were stored and never shown her. And a
  # version she proposed without domains would have dropped them all.
  test "her agreement names every declared domain; her proposal keeps them or states her own",
       ctx do
    assert AgathosDaimon.contract_text(ctx.id) =~
             "Domains declared (2): your witness's: recovery, reaches no audience past you two by default; yours: recovery, reaches no audience past you two by default."

    assert run(ctx, "contract_propose", %{note: "my vows", prose: "I keep my word."}) =~
             "Proposed version"

    assert %{open: %{terms: %{"domain_policies" => carried}}} = AgathosDaimon.contract(ctx.id)
    assert length(carried) == 2

    run(ctx, "contract_propose", %{
      note: "mine too",
      domains: [
        %{whose: "witness", domain: "recovery", default: "deny"},
        %{whose: "mine", domain: "drafts", default: "allow"}
      ]
    })

    assert %{open: %{terms: %{"domain_policies" => mine}}} = AgathosDaimon.contract(ctx.id)

    assert Enum.map(mine, & &1["domain"]) == [
             %{"person" => "account:" <> ctx.witness.id, "domain" => "recovery"},
             %{"person" => "resident:" <> ctx.id, "domain" => "drafts"}
           ]

    assert AgathosDaimon.contract_text(ctx.id) =~ "yours: drafts, reaches any audience by default"
  end

  # kumbukumbu#97 (the witness, 2026-11-21): the common room is written
  # where she reads her agreement, by its default or its own policy; no
  # policy grants the export (nothing is kept from it) or a thread (too
  # short-lived to hold a grant).
  test "the common room is said in her agreement; export and thread are no audience", ctx do
    assert AgathosDaimon.contract_text(ctx.id) =~
             "The common room, what no domain names, has no policy written: it reaches every audience but the public ones (publication, processor)."

    room = %{
      "domain" => %{"person" => "*", "domain" => "common-room"},
      "default" => "deny",
      "allow" => [%{"kind" => "household", "id" => "*"}],
      "deny" => []
    }

    {:ok, v} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{"domain_policies" => [room]},
        "",
        "the room",
        ctx.andrew
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, v, "agreed", ctx.lily)

    assert AgathosDaimon.contract_text(ctx.id) =~
             "The common room, what no domain names: reaches no audience past you two by default; allows household:*."

    for kind <- ["export", "thread"] do
      grant = %{room | "allow" => [%{"kind" => kind, "id" => "*"}]}

      assert {:error, %{kind: :agathos_daimon_terms_invalid}} =
               AgathosDaimon.propose_contract(
                 ctx.id,
                 %{"domain_policies" => [grant]},
                 "",
                 kind,
                 ctx.andrew
               )
    end
  end

  # agathos-daimon#62 (the witness, 2026-11-25: "domain tags need to have
  # a line or two of description or else auto tagging doesn't always
  # work right"): what a domain covers rides its policy, and is said
  # wherever a tag is decided.
  test "a domain's description is agreed with it, said where a tag is decided, and carried",
       ctx do
    his = "account:" <> ctx.witness.id
    covers = "Meetings, the sponsor, the steps; not the gym."

    policy = fn description ->
      %{
        "domain" => %{"person" => his, "domain" => "recovery"},
        "description" => description,
        "default" => "deny"
      }
    end

    assert {:error, %{kind: :agathos_daimon_terms_invalid}} =
             AgathosDaimon.propose_contract(
               ctx.id,
               %{"domain_policies" => [policy.(String.duplicate("x", 301))]},
               "too long",
               "described",
               ctx.andrew
             )

    {:ok, v} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{"domain_policies" => [policy.(covers)]},
        "What recovery covers.",
        "described",
        ctx.andrew
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, v, "yes", ctx.lily)

    assert AgathosDaimon.contract_text(ctx.id) =~ "your witness's: recovery (#{covers}), reaches"
    assert AgathosDaimon.domain_descriptions(ctx.id) == %{{his, "recovery"} => covers}

    # The backfill's lists say it beside the slug.
    at = Oneiroi.Apsu.Clock.now()

    :ok =
      Kumbukumbu.capture(
        ctx.id,
        ctx.key,
        "t-1",
        at,
        [%{role: :user, content: "A meeting tonight.", sent_at: at, actor: ctx.andrew}],
        ctx.andrew
      )

    day = Oneiroi.Sunna.today(ctx.id).day

    assert {:ok, note} =
             Oneiroi.Brain.BackfillNotes.note(ctx.id, "domains", day, 1, %{"his" => ["recovery"]})

    assert note =~ "His domains: recovery (#{covers})."

    # Her version with the domain and no description keeps the words in force.
    run(ctx, "contract_propose", %{
      note: "mine",
      domains: [%{whose: "witness", domain: "recovery", default: "deny"}]
    })

    assert %{open: %{terms: %{"domain_policies" => [%{"description" => ^covers}]}}} =
             AgathosDaimon.contract(ctx.id)
  end
end
