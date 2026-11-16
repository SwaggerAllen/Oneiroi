defmodule Oneiroi.Xenia.Store do
  @moduledoc "The correspondence projections and their queries, under the resident's scope."
  import Ecto.Query, only: [from: 2]

  alias Oneiroi.Repo

  defmodule Message do
    @moduledoc "A third party's message: who, from where, and the words, which are nil when its sender was blocked."
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
      field(:read_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule ReaderSites do
    @moduledoc "The reader's allowlists (xenia#16): the origins its browser may reach to read correspondence and to research."
    use Ecto.Schema
    @primary_key false
    schema "xenia_reader_sites" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:scrape, {:array, :string}, default: [])
      field(:research, {:array, :string}, default: [])
      field(:set_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The reader's allowlists as set, or nil before the witness has set them."
  defmodule Presence do
    @moduledoc "The witness's presence switch and handle (xenia#20), the follow list's last fetch and the rotation's cursor."
    use Ecto.Schema
    @primary_key false
    schema "xenia_presence" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:enabled, :boolean, default: false)
      field(:handle, :string)
      field(:set_at, :utc_datetime_usec)
      field(:follows_at, :utc_datetime_usec)
      field(:visible, :integer)
      field(:cursor, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule PresenceAccount do
    @moduledoc "An account on the follow list (xenia#20): where it is, whether it is masked and why, when it was last sampled."
    use Ecto.Schema
    @primary_key false
    schema "xenia_presence_account" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:name, :string)
      field(:host, :string)
      field(:publication_id, :integer)
      field(:author_id, :integer)
      field(:first_seen_at, :utc_datetime_usec)
      field(:followed, :boolean, default: true)
      field(:last_sampled_at, :utc_datetime_usec)
      field(:excluded, :boolean, default: false)
      field(:excluded_at, :utc_datetime_usec)
      field(:reason, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule PresencePass do
    @moduledoc "A day's pass (xenia#20): the accounts sampled, the pool, the cuts' sizes and the outbound cap."
    use Ecto.Schema
    @primary_key false
    schema "xenia_presence_pass" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:day, :string)
      field(:accounts, {:array, :string}, default: [])
      field(:pool, :integer)
      field(:ranked, :integer)
      field(:serendipity, :integer)
      field(:cap, :integer)
      field(:drawn_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule PresenceRead do
    @moduledoc "An item a pass handed the resident to read (xenia#20), with its counts, its score and its cut, and when she read it."
    use Ecto.Schema
    @primary_key false
    schema "xenia_presence_read" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:pass, :integer, primary_key: true)
      field(:item, :string, primary_key: true)
      field(:account, :string)
      field(:kind, :string)
      field(:title, :string)
      field(:url, :string)
      field(:published_at, :utc_datetime_usec)
      field(:likes, :integer, default: 0)
      field(:comments, :integer, default: 0)
      field(:restacks, :integer, default: 0)
      field(:score, :integer, default: 0)
      field(:cut, :string)
      field(:excerpt, :string)
      field(:read_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule PresenceInteraction do
    @moduledoc "A like, comment or restack the resident staged (xenia#20), and its way through the review to being sent."
    use Ecto.Schema
    @primary_key false
    schema "xenia_presence_interaction" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:pass, :integer)
      field(:item, :string)
      field(:account, :string)
      field(:kind, :string)
      field(:text, :string)
      field(:supersedes, :integer)
      field(:superseded_by, :integer)
      field(:state, :string)
      field(:comment, :string)
      field(:release_at, :utc_datetime_usec)
      field(:staged_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
      field(:sent_at, :utc_datetime_usec)
      field(:url, :string)
      field(:reason, :string)
    end

    @type t :: %__MODULE__{}
  end

  @spec reader_sites() :: ReaderSites.t() | nil
  def reader_sites, do: Repo.one(from(s in ReaderSites, limit: 1))

  defmodule Block do
    @moduledoc "A blocked identity on a platform: whose messages are counted and never kept, and which party set it."
    use Ecto.Schema
    @primary_key false
    schema "xenia_block" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:platform, :string, primary_key: true)
      field(:identity, :string, primary_key: true)
      field(:name, :string)
      field(:note, :string)
      field(:blocked_by, :string)
      field(:blocked_at, :utc_datetime_usec)
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
      field(:superseded_by, :integer)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Route do
    @moduledoc "A route of the resident's own (xenia#19): its descriptor, the file under routes/ projected."
    use Ecto.Schema
    @primary_key false
    schema "xenia_route" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:descriptor, :map)
      field(:created_by, :string)
      field(:updated_by, :string)
      field(:created_at, :utc_datetime_usec)
      field(:updated_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule RouteRun do
    @moduledoc "One asked run of a route of hers (xenia#19): open until it lands or fails."
    use Ecto.Schema
    @primary_key false
    schema "xenia_route_run" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:key, :string)
      field(:state, :string)
      field(:note, :string)
      field(:asked_by, :string)
      field(:asked_at, :utc_datetime_usec)
      field(:path, :string)
      field(:reason, :string)
      field(:done_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Profile do
    @moduledoc "A profile as the witness made, named or revoked it (xenia#19); a seeded one has a row only once he has touched it."
    use Ecto.Schema
    @primary_key false
    schema "xenia_profile" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:key, :string, primary_key: true)
      field(:label, :string)
      field(:origin, :string)
      field(:signed_in_as, :string)
      field(:revoked, :boolean, default: false)
      field(:note, :string)
      field(:set_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @spec routes() :: [Route.t()]
  def routes, do: Repo.all(from(r in Route, order_by: [r.created_at, r.key]))

  @spec route_runs(String.t() | nil) :: [RouteRun.t()]
  def route_runs(nil), do: Repo.all(from(r in RouteRun, order_by: [desc: r.number]))

  def route_runs(state),
    do: Repo.all(from(r in RouteRun, where: r.state == ^state, order_by: r.number))

  @spec route_run(pos_integer()) :: RouteRun.t() | nil
  def route_run(number), do: Repo.one(from(r in RouteRun, where: r.number == ^number))

  @spec profiles() :: [Profile.t()]
  def profiles, do: Repo.all(from(p in Profile, order_by: p.key))

  @spec messages(String.t() | nil) :: [Message.t()]
  def messages(nil), do: Repo.all(from(m in Message, order_by: [desc: m.number]))

  def messages(state),
    do: Repo.all(from(m in Message, where: m.state == ^state, order_by: [desc: m.number]))

  @spec message(pos_integer()) :: Message.t() | nil
  def message(number), do: Repo.one(from(m in Message, where: m.number == ^number))

  @spec blocks() :: [Block.t()]
  def blocks, do: Repo.all(from(b in Block, order_by: [b.platform, b.identity]))

  @spec replies(String.t() | nil) :: [Reply.t()]
  def replies(nil), do: Repo.all(from(r in Reply, order_by: [desc: r.number]))

  def replies(state),
    do: Repo.all(from(r in Reply, where: r.state == ^state, order_by: [desc: r.number]))

  # ---- presence (xenia#20) ----

  @spec presence() :: Presence.t() | nil
  def presence, do: Repo.one(from(p in Presence, limit: 1))

  @spec presence_accounts() :: [PresenceAccount.t()]
  def presence_accounts, do: Repo.all(from(a in PresenceAccount, order_by: a.key))

  @spec presence_passes(pos_integer()) :: [PresencePass.t()]
  def presence_passes(limit),
    do: Repo.all(from(p in PresencePass, order_by: [desc: p.number], limit: ^limit))

  @spec presence_pass(String.t()) :: PresencePass.t() | nil
  def presence_pass(day), do: Repo.one(from(p in PresencePass, where: p.day == ^day))

  @spec presence_reads(pos_integer()) :: [PresenceRead.t()]
  def presence_reads(pass),
    do:
      Repo.all(
        from(r in PresenceRead, where: r.pass == ^pass, order_by: [desc: r.score, asc: r.item])
      )

  @spec presence_read(pos_integer(), String.t()) :: PresenceRead.t() | nil
  def presence_read(pass, item),
    do: Repo.one(from(r in PresenceRead, where: r.pass == ^pass and r.item == ^item))

  @spec presence_interactions([String.t()] | nil) :: [PresenceInteraction.t()]
  def presence_interactions(nil),
    do: Repo.all(from(i in PresenceInteraction, order_by: [desc: i.number]))

  def presence_interactions(states),
    do:
      Repo.all(
        from(i in PresenceInteraction, where: i.state in ^states, order_by: [desc: i.number])
      )

  @spec presence_interaction(pos_integer()) :: PresenceInteraction.t() | nil
  def presence_interaction(number),
    do: Repo.one(from(i in PresenceInteraction, where: i.number == ^number))
end
