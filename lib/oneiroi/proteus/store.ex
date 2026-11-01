defmodule Oneiroi.Proteus.Store do
  @moduledoc "The bridge projections and their queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Bridge do
    @moduledoc "The resident's one bridge row: the workspace, its peers, the card as last set, the last audit, the syncs."
    use Ecto.Schema
    @primary_key false
    schema "proteus_bridge" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:workspace, :string)
      field(:peers, {:array, :string}, default: [])
      field(:provisioned_at, :utc_datetime_usec)
      field(:card_hash, :string)
      field(:card_lines, :integer)
      field(:card_source, :string)
      field(:card_set_at, :utc_datetime_usec)
      field(:last_audit_at, :utc_datetime_usec)
      field(:last_audit_moved, :boolean)
      field(:last_audit_reason, :string)
      field(:syncs, :integer, default: 0)
      field(:last_sync_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Sync do
    @moduledoc "One turn's sync to Honcho: how many messages, or why it failed."
    use Ecto.Schema
    @primary_key false
    schema "proteus_sync" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:turn_ref, :string, primary_key: true)
      field(:session_key, :string)
      field(:messages, :integer)
      field(:outcome, :string)
      field(:reason, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec bridge() :: Bridge.t() | nil
  def bridge, do: Repo.one(from(b in Bridge, limit: 1))

  @spec sync(String.t()) :: Sync.t() | nil
  def sync(turn_ref), do: Repo.one(from(s in Sync, where: s.turn_ref == ^turn_ref))

  @doc "Every turn whose last sync failed: a synced turn's row is never failed again (`Bridge`)."
  @spec failed_syncs() :: [Sync.t()]
  def failed_syncs,
    do:
      Repo.all(
        from(s in Sync, where: s.outcome == "failed", order_by: [asc: s.at, asc: s.turn_ref])
      )

  @spec syncs(pos_integer()) :: [Sync.t()]
  def syncs(limit), do: Repo.all(from(s in Sync, order_by: [desc: s.at], limit: ^limit))
end
