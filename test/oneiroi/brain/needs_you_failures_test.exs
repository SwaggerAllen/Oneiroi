defmodule Oneiroi.Brain.NeedsYouFailuresTest do
  @moduledoc """
  brain#88: a turn that failed waits on the witness in the bell, those
  refused for credit folded into one entry, every other one its own with
  the provider's reason; dismissed, it goes.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Brain.NeedsYou.Failures
  alias Oneiroi.Fixtures
  alias Oneiroi.Kumbukumbu

  @credits "nisaba_request_refused: 402 This request requires more credits, or fewer max_tokens."

  setup do
    account = Fixtures.account!()
    resident = Fixtures.resident!(account)
    me = Actor.new(:witness, account.id)
    brain = Actor.new(:resident, resident.id, "fake/model")
    {:ok, key} = Kumbukumbu.main_session(resident.id, account.id, me)
    {:ok, id: resident.id, key: key, me: me, brain: brain}
  end

  defp failures(ctx),
    do: Enum.filter(NeedsYou.list(ctx.id), &(&1.kind in ["provider_credits", "turn_failed"]))

  test "credit refusals fold into one entry; any other failure is its own, with its reason",
       ctx do
    assert failures(ctx) == []

    :ok = Kumbukumbu.fail_capture(ctx.id, ctx.key, "t-checkin", @credits, ctx.brain)
    :ok = Kumbukumbu.fail_capture(ctx.id, ctx.key, "t-reply", @credits, ctx.brain)

    :ok =
      Kumbukumbu.fail_capture(
        ctx.id,
        ctx.key,
        "t-broke",
        "nisaba_provider_failed: 502 Network connection lost.",
        ctx.brain
      )

    assert [credits, broke] = Enum.sort_by(failures(ctx), & &1.kind)
    assert %{kind: "provider_credits", ref: "openrouter", screen: "settings"} = credits
    assert credits.about.reason == @credits
    assert credits.about.what =~ "2 turn(s)"

    assert Enum.map(credits.about.failures, & &1.turn_ref) |> Enum.sort() == [
             "t-checkin",
             "t-reply"
           ]

    assert %{kind: "turn_failed", ref: "t-broke", screen: "chat"} = broke
    assert broke.about.reason =~ "502"
    assert broke.about.session_key == ctx.key and broke.about.conversation == "main"

    # Dismissed (resolved as lost), each goes.
    :ok = Kumbukumbu.resolve_failure(ctx.id, ctx.key, "t-broke", "marked_lost", "seen", ctx.me)

    for ref <- ["t-checkin", "t-reply"],
        do:
          :ok =
            Kumbukumbu.resolve_failure(ctx.id, ctx.key, ref, "marked_lost", "topped up", ctx.me)

    assert failures(ctx) == []
  end

  test "a credit refusal is told by its status and its words" do
    assert Failures.credits?(@credits)
    refute Failures.credits?("nisaba_provider_failed: 502 Network connection lost.")
    refute Failures.credits?(nil)
  end
end
