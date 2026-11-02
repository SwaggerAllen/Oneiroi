defmodule Oneiroi.Xenia.Store do
  @moduledoc "The correspondence projections and their queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Message do
    @moduledoc "A third party's message: who, from where, the words, and where the witness's reading left it."
    use Ecto.Schema
    @primary_key false
    schema "xenia_message" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:platform, :string)
      field(:account, :string)
      field(:external_id, :string)
      field(:sender, :string)
      field(:sender_name, :string)
      field(:verified, :boolean)
      field(:thread, :string)
      field(:subject, :string)
      field(:text, :string)
      field(:sent_at, :utc_datetime_usec)
      field(:received_at, :utc_datetime_usec)
      field(:received_by, :string)
      field(:state, :string)
      field(:trusted, :boolean)
      field(:note, :string)
      field(:decided_at, :utc_datetime_usec)
      field(:read_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Correspondent do
    @moduledoc "A trusted identity on a platform: whose messages reach the resident without the witness's reading."
    use Ecto.Schema
    @primary_key false
    schema "xenia_correspondent" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:platform, :string, primary_key: true)
      field(:identity, :string, primary_key: true)
      field(:name, :string)
      field(:note, :string)
      field(:trusted_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Reply do
    @moduledoc "A reply the resident drafted: where it goes, the words, and its way through the gate to being sent."
    use Ecto.Schema
    @primary_key false
    schema "xenia_reply" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:in_reply_to, :integer)
      field(:platform, :string)
      field(:account, :string)
      field(:thread, :string)
      field(:to, :string)
      field(:text, :string)
      field(:state, :string)
      field(:note, :string)
      field(:drafted_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
      field(:sent_at, :utc_datetime_usec)
      field(:sent_by, :string)
      field(:url, :string)
    end

    @type t :: %__MODULE__{}
  end

  @spec messages(String.t() | nil) :: [Message.t()]
  def messages(nil), do: Repo.all(from(m in Message, order_by: [desc: m.number]))

  def messages(state),
    do: Repo.all(from(m in Message, where: m.state == ^state, order_by: [desc: m.number]))

  @spec message(pos_integer()) :: Message.t() | nil
  def message(number), do: Repo.one(from(m in Message, where: m.number == ^number))

  @spec correspondents() :: [Correspondent.t()]
  def correspondents,
    do: Repo.all(from(c in Correspondent, order_by: [c.platform, c.identity]))

  @spec replies(String.t() | nil) :: [Reply.t()]
  def replies(nil), do: Repo.all(from(r in Reply, order_by: [desc: r.number]))

  def replies(state),
    do: Repo.all(from(r in Reply, where: r.state == ^state, order_by: [desc: r.number]))
end
