defmodule Oneiroi.Kumbukumbu.Store do
  @moduledoc """
  Memory's projections and the queries over them (conventions §6): the
  sessions, the messages, the capture failures and the context
  injections. Sessions and messages are scoped both ways (spec §6.3):
  `resident_id` is the resident's and `account_id` the account party to
  the session, which for a solo session is the steward's, so the resident
  reads everything and an account reads what it was party to. After a
  custody transfer the new steward is party to nothing that came before,
  which is the export wall (spec §6.12).
  """
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Session do
    @moduledoc "One session: its key, kind, adapter, parties and the shape of its transcript."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_session" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:account_id, :binary_id)
      field(:kind, :string)
      field(:adapter, :string)
      field(:participants, {:array, :string})
      field(:shared, :boolean, default: false)
      field(:opened_at, :utc_datetime_usec)
      field(:last_turn_at, :utc_datetime_usec)
      field(:turns, :integer, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Message do
    @moduledoc "One message of a turn, keyed by (session, sent_at, hash) as spec §3.2 carries from David."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_message" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:session_key, :string, primary_key: true)
      field(:sent_at, :utc_datetime_usec, primary_key: true)
      field(:hash, :string, primary_key: true)
      field(:account_id, :binary_id)
      field(:turn_ref, :string)
      field(:sequence, :integer)
      field(:position, :integer)
      field(:role, :string)
      field(:actor_kind, :string)
      field(:actor_id, :string)
      field(:model, :string)
      field(:content, :string)
      field(:refusal, :boolean, default: false)
    end

    @type t :: %__MODULE__{}
  end

  defmodule CaptureFailure do
    @moduledoc "A turn an adapter could not deliver whole, until retried or marked lost."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_capture_failure" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:turn_ref, :string, primary_key: true)
      field(:account_id, :binary_id)
      field(:session_key, :string)
      field(:reason, :string)
      field(:failed_at, :utc_datetime_usec)
      field(:resolved_at, :utc_datetime_usec)
      field(:how, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule ContextInjection do
    @moduledoc "One blob the memory agent put in front of the brain for a turn, with its reason (spec §5)."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_context_injection" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:turn_ref, :string, primary_key: true)
      field(:position, :integer, primary_key: true)
      field(:account_id, :binary_id)
      field(:session_key, :string)
      field(:label, :string)
      field(:tokens, :integer)
      field(:reason, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "One session by key, under whatever scope the caller holds."
  @spec session(String.t()) :: Session.t() | nil
  def session(key), do: Repo.one(from(s in Session, where: s.key == ^key))

  @doc "The sessions the scope sees, newest first."
  @spec sessions() :: [Session.t()]
  def sessions, do: Repo.all(from(s in Session, order_by: [desc: s.opened_at]))

  @doc "The messages of a session in order."
  @spec messages(String.t()) :: [Message.t()]
  def messages(key) do
    Repo.all(
      from(m in Message,
        where: m.session_key == ^key,
        order_by: [asc: m.sequence, asc: m.position]
      )
    )
  end

  @doc "The last `count` messages of a session, in order: the live transcript the brain is shown."
  @spec recent_messages(String.t(), pos_integer()) :: [Message.t()]
  def recent_messages(key, count) do
    from(m in Message,
      where: m.session_key == ^key,
      order_by: [desc: m.sequence, desc: m.position],
      limit: ^count
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc "Messages whose content holds `text`, newest first; unweighted, as spec §6.3 asks."
  @spec search(String.t(), pos_integer()) :: [Message.t()]
  def search(text, limit) do
    pattern = "%" <> String.replace(text, ~r/[%_\\]/, &("\\" <> &1)) <> "%"

    Repo.all(
      from(m in Message,
        where: ilike(m.content, ^pattern),
        order_by: [desc: m.sequence, desc: m.position],
        limit: ^limit
      )
    )
  end

  @doc "The open capture failures the scope sees, oldest first."
  @spec open_failures() :: [CaptureFailure.t()]
  def open_failures,
    do: Repo.all(from(f in CaptureFailure, where: is_nil(f.resolved_at), order_by: f.failed_at))

  @doc "What a turn drew on, in the order it was injected."
  @spec injections(String.t()) :: [ContextInjection.t()]
  def injections(turn_ref),
    do:
      Repo.all(from(i in ContextInjection, where: i.turn_ref == ^turn_ref, order_by: i.position))
end
