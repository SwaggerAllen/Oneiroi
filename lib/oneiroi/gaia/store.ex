defmodule Oneiroi.Gaia.Store do
  @moduledoc """
  Identity's projections and the queries over them (conventions §6):
  function-shaped, never generic CRUD. Every query runs under the scope
  the caller set; the two platform-scoped lookups are named in
  `Oneiroi.Gaia`.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Account do
    @moduledoc "One account; scoped by its own id."
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: false}
    schema "gaia_account" do
      field(:account_id, :binary_id)
      field(:email, :string)
      field(:password_hash, :string)
      field(:second_factor, :binary)
      field(:key_ciphertext, :binary)
      field(:key_stored_at, :utc_datetime_usec)
      field(:created_at, :utc_datetime_usec)
    end
  end

  defmodule Session do
    @moduledoc "A session by the hash of its id; the raw id is never stored."
    use Ecto.Schema
    @primary_key {:hash, :string, autogenerate: false}
    schema "gaia_session" do
      field(:account_id, :binary_id)
      field(:opened_at, :utc_datetime_usec)
      field(:expires_at, :utc_datetime_usec)
      field(:closed_at, :utc_datetime_usec)
    end
  end

  defmodule Token do
    @moduledoc "An API token by the hash of its value."
    use Ecto.Schema
    @primary_key {:hash, :string, autogenerate: false}
    schema "gaia_token" do
      field(:account_id, :binary_id)
      field(:label, :string)
      field(:issued_at, :utc_datetime_usec)
      field(:revoked_at, :utc_datetime_usec)
    end
  end

  defmodule Stewardship do
    @moduledoc "The relation from an account to a resident, with a start and an end; visible to both scopes."
    use Ecto.Schema
    @primary_key false
    schema "gaia_stewardship" do
      field(:account_id, :binary_id, primary_key: true)
      field(:resident_id, :binary_id, primary_key: true)
      field(:started_at, :utc_datetime_usec)
      field(:ended_at, :utc_datetime_usec)
    end
  end

  @doc "The account with `email`, case-insensitively, or nil."
  @spec account_by_email(String.t()) :: Account.t() | nil
  def account_by_email(email) do
    downcased = String.downcase(email)
    Repo.one(from(a in Account, where: fragment("lower(?)", a.email) == ^downcased))
  end

  @doc "The account by id, or nil."
  @spec account(String.t()) :: Account.t() | nil
  def account(id), do: Repo.get(Account, id)

  @doc "A live session by hash: open, unexpired at `now`."
  @spec live_session(String.t(), DateTime.t()) :: Session.t() | nil
  def live_session(hash, now) do
    Repo.one(
      from(s in Session, where: s.hash == ^hash and is_nil(s.closed_at) and s.expires_at > ^now)
    )
  end

  @doc "A live token by hash."
  @spec live_token(String.t()) :: Token.t() | nil
  def live_token(hash),
    do: Repo.one(from(t in Token, where: t.hash == ^hash and is_nil(t.revoked_at)))

  @doc "The resident ids an account stewards now."
  @spec stewarded(String.t()) :: [String.t()]
  def stewarded(account_id) do
    Repo.all(
      from(s in Stewardship,
        where: s.account_id == ^account_id and is_nil(s.ended_at),
        select: s.resident_id,
        order_by: s.started_at
      )
    )
  end

  @doc "Whether `account_id` stewards `resident_id` now."
  @spec steward?(String.t(), String.t()) :: boolean()
  def steward?(account_id, resident_id) do
    Repo.exists?(
      from(s in Stewardship,
        where:
          s.account_id == ^account_id and s.resident_id == ^resident_id and is_nil(s.ended_at)
      )
    )
  end
end
