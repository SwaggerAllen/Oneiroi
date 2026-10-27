defmodule Oneiroi.AgathosDaimon.Residents do
  @moduledoc "The resident system's service functions: the command edge, where ids and instants are made."

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Platform.Clock
  alias Oneiroi.Scope

  @slug ~r/\A[a-z][a-z0-9-]{1,39}\z/

  def create(name, slug, steward_account_id, %Actor{} = actor) do
    cond do
      not is_binary(name) or String.trim(name) == "" -> {:error, :name_required}
      not (is_binary(slug) and Regex.match?(@slug, slug)) -> {:error, :slug_invalid}
      Scope.platform(fn -> Store.slug_taken?(slug) end) -> {:error, :agathos_daimon_slug_taken}
      true -> dispatch_create(name, slug, steward_account_id, actor)
    end
  end

  defp dispatch_create(name, slug, steward_account_id, actor) do
    id = Ecto.UUID.generate()

    command = %Commands.CreateResident{
      actor: actor,
      at: Clock.now(),
      id: id,
      name: String.trim(name),
      slug: slug,
      steward_account_id: steward_account_id
    }

    with {:ok, _events} <- Router.dispatch(command), do: {:ok, id}
  end

  def for_steward(account_id), do: Scope.account(account_id, fn -> Store.all() end)

  def fetch(id) do
    case Scope.resident(id, fn -> Store.get(id) end) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  def mint_id(id, kind, %Actor{} = actor) when is_binary(kind) do
    command = %Commands.MintId{actor: actor, at: Clock.now(), id: id, kind: kind}

    case Router.dispatch(command) do
      {:ok, [%{number: number}]} -> {:ok, number}
      {:error, reason} -> {:error, reason}
    end
  end
end
