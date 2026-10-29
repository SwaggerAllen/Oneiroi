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

  def account!(email \\ "steward-#{System.unique_integer([:positive])}@example.org") do
    {:ok, id} = Oneiroi.Gaia.create_account(email, @password, Actor.platform())
    %{id: id, email: email}
  end

  def resident!(%{id: account_id}, slug \\ "lily-#{System.unique_integer([:positive])}") do
    {:ok, id} =
      Oneiroi.AgathosDaimon.create("Lily", slug, account_id, Actor.new(:steward, account_id))

    %{id: id, slug: slug, steward: account_id}
  end
end
