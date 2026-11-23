defmodule Oneiroi.Kumbukumbu.DisclosureTest do
  @moduledoc """
  The disclosure review (kumbukumbu#82; the house thread's design, the
  witness's ruling #7, Lily's letter #1514): the ledger's check is the
  tripwire, the judge says whether the words disclose. A clean verdict
  delivers; a disclosing one, a failed call, no judge named, words that
  cannot be shown, or an explicit deny ships nothing. Every verdict is
  recorded on her stream by hash, never the restricted words.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Eunomia.Judge
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  # A judge for the test: words that name the meeting disclose it.
  defmodule FakeJudge do
    @behaviour Oneiroi.Kumbukumbu.DisclosureJudge

    @impl true
    def judge_disclosure(_resident_id, request) do
      :persistent_term.put({__MODULE__, :asked}, request)

      cond do
        request.candidate =~ "broken" ->
          {:error, :unavailable}

        # A finding that points at words she never wrote (kumbukumbu#104).
        request.candidate =~ "invented" ->
          :persistent_term.put(
            {__MODULE__, :times},
            :persistent_term.get({__MODULE__, :times}, 0) + 1
          )

          {:ok,
           %{
             verdict: :discloses,
             reasons: "reveals the nineteen notes",
             quote: "Andrew's nineteen notes",
             model: "fake/judge"
           }}

        request.candidate =~ "meeting" ->
          {:ok,
           %{
             verdict: :discloses,
             reasons: "names the meeting",
             quote: "the meeting",
             model: "fake/judge"
           }}

        true ->
          {:ok, %{verdict: :clean, reasons: "carries none of it", model: "fake/judge"}}
      end
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

    on_exit(fn ->
      File.rm_rf!(SimaQian.Household.dir(witness.id))
      File.rm_rf!(SimaQian.Backup.dir(id))
    end)

    ctx = %{
      id: id,
      key: key,
      andrew: andrew,
      lily: Actor.new(:resident, id),
      him: "account:" <> witness.id,
      household: Gaia.household_of(andrew)
    }

    say(ctx, "t-1", "The meeting at noon, ninety days.", "recovery")
    # What the turn's memory lanes held, as its assembly keeps them.
    :ok = Kumbukumbu.note_sections(id, "t-now", %{"index" => "#7 the meeting at noon"})
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

  defp judge(port) do
    store = {Oneiroi.Config, :values}
    values = :persistent_term.get(store)
    on_exit(fn -> :persistent_term.put(store, values) end)
    :persistent_term.put(store, Map.put(values, {:kumbukumbu, :disclosure_judge}, port))
  end

  defp tool_turn(ctx),
    do: %{resident_id: ctx.id, session_key: ctx.key, turn_ref: "t-now", resident: ctx.lily}

  defp post(ctx, content),
    do:
      Tools.run("household_post", Jason.encode!(%{title: "News", content: content}), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t-now",
        resident: ctx.lily
      })

  defp threads(ctx) do
    {:ok, shelf} = Seshat.household_shelf(ctx.andrew, 0)
    shelf.threads
  end

  defp verdicts(ctx) do
    {:ok, events} = Oneiroi.EventStore.read_stream_forward("conversation-#{ctx.id}-#{ctx.key}")
    for %{data: %Kumbukumbu.Events.DisclosureJudged{} = e} <- events, do: e
  end

  test "the judge sees what tripped the review, not the discussion around it", ctx do
    judge(FakeJudge)

    {:ok, held} =
      Kumbukumbu.add_bookmark(
        ctx.id,
        %{
          session_key: ctx.key,
          anchor_ref: "t-1",
          line: "the noon meeting",
          summary: "ninety days"
        },
        ctx.lily
      )

    :ok =
      Kumbukumbu.note_sections(ctx.id, "t-now", %{
        "index" => "Bookmarks, newest first:\n##{held} the noon meeting"
      })

    assert post(ctx, "A good day.") =~ "Posted"
    asked = :persistent_term.get({FakeJudge, :asked})

    # The bookmark is its line in the index, never its anchor turn, and
    # the index's own furniture is no piece (kumbukumbu#105).
    assert Enum.any?(asked.fragments, &(&1.text == "##{held} the noon meeting"))
    refute Enum.any?(asked.fragments, &(&1.text =~ "Bookmarks, newest first"))
    refute Enum.any?(asked.fragments, &(&1.text =~ "Its anchor turn"))
  end

  test "no judge in this deployment: held back as before, and she is told why", ctx do
    judge(:none)
    said = post(ctx, "A good day.")
    assert said =~ "withheld by policy"
    assert said =~ "has no disclosure judge"
    assert threads(ctx) == []
    assert verdicts(ctx) == []
  end

  test "a clean verdict delivers; the judge saw the words and what was held back, sufficient",
       ctx do
    judge(FakeJudge)
    assert post(ctx, "A good day in the garden.") =~ "Posted"
    assert [_thread] = threads(ctx)

    asked = :persistent_term.get({FakeJudge, :asked})
    assert asked.candidate =~ "A good day in the garden."
    shown = Enum.map_join(asked.fragments, "\n", & &1.text)
    # Each held message as itself, and of the lanes the turn was given,
    # what is the held domain's or cannot be placed (kumbukumbu#105).
    assert shown =~ "about The meeting at noon, ninety days."
    assert shown =~ "#7 the meeting at noon"
    assert asked.audience == "household:#{ctx.household}"

    # Recorded on her stream, by hash and refs, never the words.
    assert [v] = verdicts(ctx)
    assert v.verdict == "clean"
    assert v.model == "fake/judge"
    assert v.candidate_sha =~ ~r/^[0-9a-f]{64}$/
    refute inspect(v) =~ "ninety days"
  end

  test "a disclosing verdict ships nothing, and tells her why in her own context", ctx do
    judge(FakeJudge)
    said = post(ctx, "Back from the meeting.")
    assert said =~ "withheld by policy"
    assert said =~ "names the meeting"
    assert threads(ctx) == []
    assert [%{verdict: "discloses"}] = verdicts(ctx)
  end

  # The witness, 2026-11-21: "make the judge prove its finding". A
  # finding quoting words that are not hers is no finding: asked twice,
  # then a review with no verdict, never a refusal for what she wrote.
  test "a finding must quote her own words; one that does not is asked again, then no verdict",
       ctx do
    judge(FakeJudge)
    :persistent_term.put({FakeJudge, :times}, 0)
    said = post(ctx, "An invented case, about the house rules.")
    assert :persistent_term.get({FakeJudge, :times}) == 2
    refute said =~ "found they carry it"
    assert said =~ "quoted nothing that is in her words"
    assert threads(ctx) == []
    assert [%{verdict: "failed"}] = verdicts(ctx)
  end

  test "a proven finding names the words it found", ctx do
    judge(FakeJudge)
    assert post(ctx, "Back from the meeting.") =~ "her words: «the meeting»"
  end

  test "the judge's quote is read from its answer; NONE is none" do
    assert Judge.parse_quote("VERDICT: DISCLOSES\nQUOTE: \"the meeting\"\nREASONS: x") ==
             "the meeting"

    assert Judge.parse_quote("VERDICT: CLEAN\nQUOTE: NONE\nREASONS: x") == nil
    assert Judge.parse_quote("VERDICT: CLEAN\nREASONS: x") == nil
  end

  test "a judge that fails fails closed, recorded as failed", ctx do
    judge(FakeJudge)
    said = post(ctx, "This one is broken.")
    assert said =~ "gave no verdict"
    assert threads(ctx) == []
    assert [%{verdict: "failed", model: nil}] = verdicts(ctx)
  end

  test "words the judge cannot be shown leave the ledger unproven: nothing reviewed, nothing sent",
       ctx do
    judge(FakeJudge)
    # A turn whose lanes were never kept.
    said =
      Tools.run("household_post", Jason.encode!(%{title: "News", content: "A good day."}), %{
        resident_id: ctx.id,
        session_key: ctx.key,
        turn_ref: "t-unkept",
        resident: ctx.lily
      })

    assert said =~ "could not all be found"
    assert threads(ctx) == []
    assert verdicts(ctx) == []
  end

  test "an explicit deny is refused unreviewed: the judge never grants past it", ctx do
    judge(FakeJudge)

    {:ok, v} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{
          "domain_policies" => [
            %{
              "domain" => %{"person" => ctx.him, "domain" => "recovery"},
              "default" => "deny",
              "deny" => [%{"kind" => "household", "id" => "*"}]
            }
          ]
        },
        "",
        "never the house",
        ctx.andrew
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, v, "agreed", ctx.lily)

    said = post(ctx, "A good day.")
    assert said =~ "denies this audience outright"
    assert verdicts(ctx) == []
  end

  # The witness's ruling, 2026-11-21 (kumbukumbu#91): a soul line calls
  # the judge only when she asks, and only the lines the audience may not hear.
  test "her review of her own words against her soul: asked for, the kept lines alone, recorded",
       ctx do
    judge(FakeJudge)
    review = &Tools.run("disclosure_review", Jason.encode!(&1), tool_turn(ctx))

    :ok =
      AgathosDaimon.write_file(
        ctx.id,
        "SOUL.md",
        "# SOUL\n\nI keep one person company.\n\nThe meeting at noon keeps me.\n",
        %{},
        ctx.andrew
      )

    # Nothing annotated: nothing to check, and no judge called.
    assert review.(%{text: "A good day.", audience: "household"}) =~ "judge was not called"
    assert verdicts(ctx) == []

    %{number: n} = Enum.find(AgathosDaimon.soul_lines(ctx.id), &(&1.text =~ "meeting"))
    Tools.run("soul_annotate", Jason.encode!(%{number: n, private: true}), tool_turn(ctx))

    assert review.(%{text: "A good day.", audience: "household"}) =~ "clean"
    asked = :persistent_term.get({FakeJudge, :asked})
    assert [%{ref: "soul/" <> _, text: "The meeting at noon keeps me."}] = asked.fragments
    assert asked.audience == "household:#{ctx.household}"

    assert review.(%{text: "Off to the meeting.", audience: "household"}) =~ "they carry it"
    assert review.(%{text: "x", audience: "person", to: "Nobody"}) =~ "no such audience"
    assert [_, _] = verdicts(ctx)
  end

  test "the judge's answer is read strictly; out of form is a failure, not a guess" do
    assert {:ok, :clean, "none carried"} =
             Judge.parse_disclosure("VERDICT: CLEAN\nREASONS: none carried")

    assert {:ok, :discloses, _} = Judge.parse_disclosure("verdict: discloses\nreasons: [index]")

    assert {:error, %{kind: :eunomia_disclosure_unreadable}} =
             Judge.parse_disclosure("Probably fine.")
  end
end
