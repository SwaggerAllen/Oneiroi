defmodule Oneiroi.Fixtures do
  @moduledoc "Accounts and residents for tests, through the same exports the API uses."

  # Test support reaches every system the tests do; its own boundary, so
  # the core never depends on it.
  use Boundary,
    top_level?: true,
    deps: [Oneiroi, Oneiroi.Gaia, Oneiroi.SimaQian, Oneiroi.AgathosDaimon, Oneiroi.Kumbukumbu]

  alias Oneiroi.Actor

  @password "correct horse battery staple"

  def password, do: @password

  def account!(email \\ "witness-#{System.unique_integer([:positive])}@example.org") do
    {:ok, id} = Oneiroi.Gaia.create_account(email, @password, Actor.platform())
    %{id: id, email: email}
  end

  def resident!(%{id: account_id}, slug \\ "lily-#{System.unique_integer([:positive])}") do
    {:ok, id} =
      Oneiroi.AgathosDaimon.create("Lily", slug, account_id, Actor.new(:witness, account_id))

    %{id: id, slug: slug, witness: account_id}
  end

  @doc """
  Puts a first agreement in force for a resident, proposed by her witness
  and agreed by her: a resident with none is held from her household
  (agathos-daimon#51), so a test of the house agrees one first.
  """
  def agreed!(resident_id, witness_account_id) do
    witness = Actor.new(:witness, witness_account_id)

    {:ok, v} =
      Oneiroi.AgathosDaimon.propose_contract(
        resident_id,
        %{},
        "A first agreement.",
        "for the house",
        witness
      )

    :ok =
      Oneiroi.AgathosDaimon.agree_contract(
        resident_id,
        v,
        "yes",
        Actor.new(:resident, resident_id)
      )

    resident_id
  end

  @doc """
  Declares `slugs` in the resident's agreement (agathos-daimon#57), each
  for the witness's life and hers, default deny: a test may then tag,
  classify and annotate them. Agreed as a new version.
  """
  def declare_domains!(resident_id, witness_account_id, slugs) do
    witness = Actor.new(:witness, witness_account_id)

    policies =
      for slug <- slugs,
          person <- ["account:" <> witness_account_id, "resident:" <> resident_id],
          do: %{"domain" => %{"person" => person, "domain" => slug}, "default" => "deny"}

    {:ok, v} =
      Oneiroi.AgathosDaimon.propose_contract(
        resident_id,
        %{"domain_policies" => policies},
        "Domains declared for the test.",
        "declared",
        witness
      )

    :ok =
      Oneiroi.AgathosDaimon.agree_contract(
        resident_id,
        v,
        "yes",
        Actor.new(:resident, resident_id)
      )

    resident_id
  end
end
