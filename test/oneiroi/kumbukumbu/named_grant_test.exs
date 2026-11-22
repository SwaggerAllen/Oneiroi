defmodule Oneiroi.Kumbukumbu.NamedGrantTest do
  @moduledoc """
  kumbukumbu#102 (Scarlett's report #25, 2026-11-21): a household is
  granted by its slug on the agreement screen ("household:strut") and
  resolved by its id at delivery. The named grant now matches, and a
  refusal names the policies it checked.
  """
  use Oneiroi.DataCase, async: false

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Fixtures
  alias Oneiroi.Gaia
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Kumbukumbu.Audience
  alias Oneiroi.Seshat

  setup do
    Process.put(Oneiroi.Gaia.Door, "platform-test-#{System.unique_integer([:positive])}")
    witness = Fixtures.account!()
    andrew = Actor.new(:witness, witness.id)
    {:ok, _} = Seshat.household_propose_contract(andrew, "We share this house.", "founding")
    slug = "strut#{System.unique_integer([:positive])}"
    :ok = Gaia.name_household(witness.id, slug, andrew)
    resident = Fixtures.resident!(witness)
    {:ok, id: resident.id, witness: witness, andrew: andrew, slug: slug}
  end

  defp agree!(ctx, allow) do
    his = "account:" <> ctx.witness.id

    {:ok, v} =
      AgathosDaimon.propose_contract(
        ctx.id,
        %{
          "domain_policies" => [
            %{
              "domain" => %{"person" => his, "domain" => "recovery"},
              "default" => "deny",
              "allow" => allow
            }
          ]
        },
        "",
        "recovery for the house",
        ctx.andrew
      )

    :ok = AgathosDaimon.agree_contract(ctx.id, v, "yes", Actor.new(:resident, ctx.id))
    his
  end

  defp decide(ctx, his) do
    input = %{id: "x", ref: "x", labels: [%{person: his, domain: "recovery"}]}
    Audience.decide_for(ctx.id, [input], Kumbukumbu.audience("household", ctx.witness.id), :hard)
  end

  test "a grant naming the household by its slug reaches it by its id", ctx do
    his = agree!(ctx, [%{"kind" => "household", "id" => ctx.slug}])
    assert decide(ctx, his).withheld == []
  end

  test "a grant naming it by its id still reaches it; another house's slug does not", ctx do
    his = agree!(ctx, [%{"kind" => "household", "id" => ctx.witness.id}])
    assert decide(ctx, his).withheld == []

    his = agree!(ctx, [%{"kind" => "household", "id" => "elsewhere"}])
    assert [%{reason: :not_allowed}] = decide(ctx, his).withheld
  end
end
