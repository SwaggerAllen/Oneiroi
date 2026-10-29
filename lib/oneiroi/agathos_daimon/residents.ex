defmodule Oneiroi.AgathosDaimon.Residents do
  @moduledoc "The resident system's service functions: the command edge, where ids and instants are made."

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.AdapterPrincipal
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Error
  alias Oneiroi.AgathosDaimon.Resident
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
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

  @doc "Every active resident, under the platform scope by name: the roster a nightly job walks."
  def active, do: Scope.platform(fn -> Enum.filter(Store.all(), &(&1.state == "active")) end)

  def mint_id(id, kind, %Actor{} = actor) when is_binary(kind) do
    command = %Commands.MintId{actor: actor, at: Clock.now(), id: id, kind: kind}

    case Router.dispatch(command) do
      {:ok, [%{number: number}]} -> {:ok, number}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Pins the chat model (spec §6.4): `reason` is `run` for a regression favourite, `steward` otherwise."
  def pin_model(id, model, reason, %Actor{} = actor) do
    command = %Commands.PinModel{
      actor: actor,
      at: Clock.now(),
      id: id,
      model: model,
      reason: reason
    }

    case Router.dispatch(command) do
      {:ok, _} ->
        :ok

      {:error, :model_invalid} ->
        {:error, Error.new(:agathos_daimon_model_invalid)}

      {:error, :reason_invalid} ->
        {:error, Error.new(:agathos_daimon_model_invalid, reason: reason)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Records that the resident was told of the model change; idempotent."
  def model_told(id, %Actor{} = actor) do
    command = %Commands.RecordModelTold{actor: actor, at: Clock.now(), id: id, model: nil}
    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  @doc "Sets the resident's time zone (spec §6.7): an IANA name the database knows, checked by shifting a known instant into it."
  def set_timezone(id, zone, %Actor{} = actor) do
    with :ok <- zone_ok(zone) do
      command = %Commands.SetTimezone{actor: actor, at: Clock.now(), id: id, timezone: zone}
      with {:ok, _} <- Router.dispatch(command), do: :ok
    end
  end

  defp zone_ok(zone) when is_binary(zone) do
    case DateTime.shift_zone(~U[2026-01-01 00:00:00Z], zone) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, Error.new(:agathos_daimon_timezone_invalid)}
    end
  end

  defp zone_ok(_zone), do: {:error, Error.new(:agathos_daimon_timezone_invalid)}

  @doc "Registers an adapter with a role; returns the token, shown once. Registering again rotates it."
  def register_adapter(id, adapter, role, %Actor{} = actor) do
    raw = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    command = %Commands.RegisterAdapter{
      actor: actor,
      at: Clock.now(),
      id: id,
      adapter: adapter,
      role: role,
      token_hash: hash(raw)
    }

    case Router.dispatch(command) do
      {:ok, _} ->
        {:ok, raw}

      {:error, :adapter_invalid} ->
        {:error, Error.new(:agathos_daimon_adapter_invalid, adapter: adapter)}

      {:error, :role_invalid} ->
        {:error, Error.new(:agathos_daimon_adapter_invalid, role: role, roles: Resident.roles())}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def revoke_adapter(id, adapter, %Actor{} = actor) do
    command = %Commands.RevokeAdapter{actor: actor, at: Clock.now(), id: id, adapter: adapter}

    case Router.dispatch(command) do
      {:ok, _} ->
        :ok

      {:error, :no_such_adapter} ->
        {:error, Error.new(:agathos_daimon_no_such_adapter, adapter: adapter)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The adapter a bearer token names, or `:error`. A platform-scope read by name (gaia #8)."
  def authenticate_adapter(raw) when is_binary(raw) do
    Scope.platform(fn ->
      case Store.live_adapter(hash(raw)) do
        nil ->
          :error

        a ->
          {:ok, %AdapterPrincipal{resident_id: a.resident_id, adapter: a.adapter, role: a.role}}
      end
    end)
  end

  def authenticate_adapter(_raw), do: :error

  def adapters(id), do: Scope.resident(id, fn -> Store.adapters() end)

  defp hash(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
end
