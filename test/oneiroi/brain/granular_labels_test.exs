defmodule Oneiroi.Brain.GranularLabelsTest do
  @moduledoc """
  The witness, 2026-11-25: "we need to make the domains carried by
  sections more granular … each journal row gets its own domains", "only
  send the judge the pieces in the conflicting domain", cut "takes the
  domain just because it's in context", be "much stricter about citation
  and feedback calls", and "agents need a way to redo the generation with
  the offending entries removed".

  - kumbukumbu#111: a section of pieces is decided piece by piece; for an
    audience, only the held pieces are cut out of it.
  - kumbukumbu#112: a record takes its writing turn's domain, what it
    cites and what its turn's feedback used; feedback names only what the
    turn was shown; the labels pass overwrites by the same sources, the
    common room where none speaks, her classification standing.
  - kumbukumbu#113: a withheld delivery can be redone as a fresh turn
    composed for its audience.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.LabelPropagation
  alias Oneiroi.Brain.Pieces
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu
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
     day: Oneiroi.Sunna.today(resident.id).day,
     his: "account:" <> witness.id}
  end

  defp say(ctx, ref, words, domain) do
    :ok = Kumbukumbu.tag_domain(ctx.id, ctx.key, ref, ctx.his, domain, ctx.andrew)
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

  defp run(ctx, name, args, ref),
    do:
      Tools.run(name, Jason.encode!(args), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: ref,
        started_at: Clock.now(),
        resident: ctx.brain
      })

  defp rows(ctx), do: Seshat.journal_day(ctx.id, ctx.day).entries

  test "a section of pieces is decided piece by piece; for an audience only the held ones are cut",
       ctx do
    recovery = %{
      ref: "journal/d/1",
      labels: [%{"person" => ctx.his, "domain" => "recovery"}],
      text: "- (1) The meeting."
    }

    common = %{
      ref: "journal/d/2",
      labels: [%{"kind" => "common_room"}],
      text: "- (2) The garden."
    }

    text = "# d\n\n" <> recovery.text <> "\n" <> common.text <> "\n"
    household = Kumbukumbu.audience("household", Ecto.UUID.generate())

    kept =
      Kumbukumbu.assemble_for(
        ctx.id,
        ctx.key,
        "t-for",
        household,
        [{"journal", {:pieces, [recovery, common]}, text}],
        []
      )

    assert "journal" in kept.sections
    assert kept.cut == %{"journal" => ["journal/d/1"]}

    # A piece's undeclared domain is the common room; one kept nothing is unclassified.
    assert [%{"kind" => "common_room"}] =
             Pieces.labels(ctx.id, [%{"person" => ctx.his, "domain" => "golf"}])

    assert [%{"kind" => "unclassified"}] = Pieces.labels(ctx.id, nil)
  end

  test "a row takes its turn's domain and what it cites, never what sat beside it", ctx do
    {:ok, %{slug: slug}} = AgathosDaimon.fetch(ctx.id)
    say(ctx, "t-1", "The meeting at noon.", "recovery")
    # The conversation moves back to the common room; the window still holds t-1.
    say(ctx, "t-2", "The garden.", nil)

    run(ctx, "journal_add", %{day: ctx.day, kind: "note", text: "Watered the tomatoes."}, "t-3")

    run(
      ctx,
      "journal_add",
      %{day: ctx.day, kind: "note", text: "After #{slug}:transcript/#{ctx.key}/t-1."},
      "t-4"
    )

    [plain, citing] = rows(ctx)
    assert plain.labels == [%{"kind" => "common_room"}]
    assert citing.labels == [%{"person" => ctx.his, "domain" => "recovery"}]
  end

  test "feedback names only what the turn was shown, and labels what the turn wrote", ctx do
    say(ctx, "t-1", "The meeting at noon.", "recovery")
    say(ctx, "t-2", "The garden.", nil)

    {:ok, n} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{
          session_key: ctx.key,
          anchor_ref: "t-1",
          line: "the noon meeting",
          summary: "ninety days"
        },
        ctx.brain
      )

    # This turn was shown the bookmark in its index.
    pieces = Pieces.bookmarks(ctx.id, [{n, "##{n} the noon meeting"}])
    :ok = Kumbukumbu.note_pieces(ctx.id, "t-3", "index", pieces)

    run(ctx, "journal_add", %{day: ctx.day, kind: "note", text: "A quiet evening."}, "t-3")
    assert [%{labels: [%{"kind" => "common_room"}]}] = rows(ctx)

    assert run(ctx, "memory_feedback", %{used: [n + 40]}, "t-3") =~ "not in front of you"
    assert run(ctx, "memory_feedback", %{used: [n]}, "t-3") =~ "helped"

    # The row its turn wrote now carries what that turn used.
    assert [%{labels: [%{"person" => p, "domain" => "recovery"}]}] = rows(ctx)
    assert p == ctx.his
  end

  test "the pass overwrites by its sources: kept context is dropped, her classification stands",
       ctx do
    # Written with the whole context's labels, as before kumbukumbu#112.
    {:ok, _} =
      Seshat.journal_add(ctx.id, ctx.day, "note", "Kept everything.", nil, nil, ctx.brain, %{
        labels: [%{"person" => ctx.his, "domain" => "recovery"}, %{"kind" => "unclassified"}]
      })

    {:ok, _} = Seshat.journal_add(ctx.id, ctx.day, "note", "Hers to say.", ctx.brain)
    [one, two] = rows(ctx)
    classified = "#{ctx.day}/#{two.number}"
    his = {ctx.his, "recovery"}
    :ok = Kumbukumbu.classify_record(ctx.id, "journal", classified, his, "mine", ctx.brain)

    assert {:ok, _} = LabelPropagation.run(ctx.id, ctx.day, ctx.day)

    first = "#{ctx.day}/#{one.number}"

    assert %{^first => [%{"kind" => "common_room"}], ^classified => [%{"domain" => "recovery"}]} =
             Kumbukumbu.derived_labels(ctx.id, "journal", [first, classified])
  end

  test "a withheld delivery is redone by name, with what to do; a trial queues nothing", ctx do
    assert run(ctx, "delivery_redo", %{audience: "household", ask: ""}, "t-1") =~ "Not done"

    assert Tools.run(
             "delivery_redo",
             Jason.encode!(%{audience: "workspace", to: "w-1", ask: "Finish 14.1."}),
             %{
               resident_id: ctx.id,
               session_key: ctx.key,
               turn_ref: "t-1",
               resident: ctx.brain,
               trial?: true
             }
           ) =~ "Queued"
  end
end
