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

        request.candidate =~ "meeting" ->
          {:ok, %{verdict: :discloses, reasons: "names the meeting", model: "fake/judge"}}

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
    # The message's whole turn, and the lanes the turn was given.
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

  test "a judge that fails fails closed, recorded as failed", ctx do
    judge(FakeJudge)
    said = post(ctx, "This one is broken.")
    assert said =~ "could not clear them"
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

  test "the judge's answer is read strictly; out of form is a failure, not a guess" do
    assert {:ok, :clean, "none carried"} =
             Judge.parse_disclosure("VERDICT: CLEAN\nREASONS: none carried")

    assert {:ok, :discloses, _} = Judge.parse_disclosure("verdict: discloses\nreasons: [index]")

    assert {:error, %{kind: :eunomia_disclosure_unreadable}} =
             Judge.parse_disclosure("Probably fine.")
  end
end
