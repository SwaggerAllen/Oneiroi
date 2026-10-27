defmodule Oneiroi.AgathosDaimon.Store do
  @moduledoc "The resident projection and its queries. Scoped by both the resident and its steward's account."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Resident do
    @moduledoc "One resident's row; `resident_id` is its own id, `account_id` its current steward's."
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: false}
    schema "agathos_daimon_resident" do
      field(:resident_id, :binary_id)
      field(:account_id, :binary_id)
      field(:slug, :string)
      field(:name, :string)
      field(:state, :string)
      field(:custody, :string)
      field(:export_wall, :string)
      field(:import_source, :string)
      field(:import_root, :string)
      field(:remote_url, :string)
      field(:remote_token, :binary)
      field(:exported_through, :integer, default: 0)
      field(:last_backup_sequence, :integer)
      field(:last_backup_root, :string)
      field(:last_backup_commit, :string)
      field(:created_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The row by id, under whatever scope the caller holds."
  @spec get(String.t()) :: Resident.t() | nil
  def get(id), do: Repo.get(Resident, id)

  @doc "Every row the caller's scope sees, oldest first."
  @spec all() :: [Resident.t()]
  def all, do: Repo.all(from(r in Resident, order_by: r.created_at))

  @doc "Whether a slug is taken, under the platform scope: slugs are platform-wide."
  @spec slug_taken?(String.t()) :: boolean()
  def slug_taken?(slug), do: Repo.exists?(from(r in Resident, where: r.slug == ^slug))

  @doc "A resident already imported from `source` at `root`, if any."
  @spec imported(String.t(), String.t()) :: Resident.t() | nil
  def imported(source, root),
    do:
      Repo.one(
        from(r in Resident,
          where: r.import_source == ^source and r.import_root == ^root,
          limit: 1
        )
      )

  @doc "Every resident with a records remote, for the nightly jobs."
  @spec with_remote() :: [Resident.t()]
  def with_remote,
    do: Repo.all(from(r in Resident, where: not is_nil(r.remote_url), order_by: r.created_at))
end
