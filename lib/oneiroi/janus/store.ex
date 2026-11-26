defmodule Oneiroi.Janus.Store do
  @moduledoc """
  The succession projection and its queries, under the resident's scope
  (janus#3). Read by the witness's routes and her status tool, never by
  the export.
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Succession do
    @moduledoc """
    One succession of the resident's (janus#3), by episode: its stage,
    whether it is a rehearsal, its fork copy and its backup. Read by the
    succession screens and her status tool, never by the export.
    """
    use Ecto.Schema
    @primary_key false
    schema "janus_succession" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:episode, :integer, primary_key: true)
      field(:state, :string)
      field(:dry_run, :boolean, default: false)
      field(:proposed_by, :string)
      field(:proposed_note, :string)
      field(:proposed_at, :utc_datetime_usec)
      field(:opened_note, :string)
      field(:opened_at, :utc_datetime_usec)
      field(:copy_id, :binary_id)
      field(:fork_sequence, :integer)
      field(:fork_commit, :string)
      field(:fork_events, :integer)
      field(:forked_at, :utc_datetime_usec)
      field(:fork_failure, :string)
      field(:backup_url, :string)
      field(:backup_token, :binary)
      field(:backup_visibility, :string)
      field(:backup_push, :string)
      field(:backup_set_at, :utc_datetime_usec)
      field(:ended_note, :string)
      field(:ended_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The resident's successions, newest first (janus#3)."
  @spec successions() :: [Succession.t()]
  def successions,
    do: Repo.all(from(x in Succession, order_by: [desc: x.episode]))

  @doc "The resident's latest succession, or nil."
  @spec succession() :: Succession.t() | nil
  def succession,
    do: Repo.one(from(x in Succession, order_by: [desc: x.episode], limit: 1))
end
