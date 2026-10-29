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
      field(:root_mismatched_at, :utc_datetime_usec)
      field(:first_contact_at, :utc_datetime_usec)
      field(:formation_until, :utc_datetime_usec)
      field(:chat_model, :string)
      field(:model_pinned_at, :utc_datetime_usec)
      field(:model_told, :boolean, default: true)
      field(:timezone, :string, default: "Etc/UTC")
      field(:created_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule IdentityFile do
    @moduledoc "One identity file as last written, with the origin of its first seed and who wrote it last."
    use Ecto.Schema
    @primary_key false
    schema "agathos_daimon_file" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:name, :string, primary_key: true)
      field(:content, :string)
      field(:origin, :string)
      field(:model, :string)
      field(:prompt, :string)
      field(:version, :integer, default: 1)
      field(:written_by_kind, :string)
      field(:written_by_id, :string)
      field(:written_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Adapter do
    @moduledoc "A registered adapter: its role and the hash of its token, live until revoked."
    use Ecto.Schema
    @primary_key false
    schema "agathos_daimon_adapter" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:adapter, :string, primary_key: true)
      field(:role, :string)
      field(:token_hash, :string)
      field(:registered_at, :utc_datetime_usec)
      field(:revoked_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule SoulEdit do
    @moduledoc "A steward's proposed edit after first contact, open until the resident accepts or declines."
    use Ecto.Schema
    @primary_key false
    schema "agathos_daimon_soul_edit" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:file, :string)
      field(:content, :string)
      field(:note, :string)
      field(:state, :string, default: "open")
      field(:proposed_by_kind, :string)
      field(:proposed_by_id, :string)
      field(:decided_note, :string)
      field(:proposed_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
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

  @doc "The resident's identity files, by name."
  @spec files() :: [IdentityFile.t()]
  def files, do: Repo.all(from(f in IdentityFile, order_by: f.name))

  @doc "One identity file."
  @spec file(String.t()) :: IdentityFile.t() | nil
  def file(name), do: Repo.one(from(f in IdentityFile, where: f.name == ^name))

  @doc "The open soul-edit proposals, oldest first."
  @spec open_soul_edits() :: [SoulEdit.t()]
  def open_soul_edits,
    do: Repo.all(from(e in SoulEdit, where: e.state == "open", order_by: e.proposed_at))

  @doc "The resident's adapters, live and revoked."
  @spec adapters() :: [Adapter.t()]
  def adapters, do: Repo.all(from(a in Adapter, order_by: a.adapter))

  @doc "The live adapter presenting a token hash, under the platform scope: the resident is not known until it answers."
  @spec live_adapter(String.t()) :: Adapter.t() | nil
  def live_adapter(hash),
    do:
      Repo.one(
        from(a in Adapter, where: a.token_hash == ^hash and is_nil(a.revoked_at), limit: 1)
      )
end
