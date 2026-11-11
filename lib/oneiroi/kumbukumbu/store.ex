defmodule Oneiroi.Kumbukumbu.Store do
  @moduledoc """
  Memory's projections and the queries over them (conventions §6): the
  sessions, the messages, the capture failures and the context
  injections. Sessions and messages are scoped both ways (spec §6.3):
  `resident_id` is the resident's and `account_id` the account party to
  the session, which for a solo session is the witness's, so the resident
  reads everything and an account reads what it was party to. After a
  custody transfer the new witness is party to nothing that came before,
  which is the export wall (spec §6.12).
  """
  import Ecto.Query, only: [from: 2]
  import Pgvector.Ecto.Query, only: [cosine_distance: 2]

  alias Oneiroi.Kumbukumbu.Conversation
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
      field(:domain, :string)
      field(:label, :string)
      field(:runtime, :string)
      field(:shared, :boolean, default: false)
      field(:private, :boolean, default: false)
      field(:opened_at, :utc_datetime_usec)
      field(:last_turn_at, :utc_datetime_usec)
      field(:turns, :integer, default: 0)
      field(:summary, :string)
      field(:compacted_through, :integer, default: 0)
      field(:open_turn_ref, :string)
      field(:open_turn_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule React do
    @moduledoc "The witness's react on a message or letter of hers (kumbukumbu#56), and when it was told."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_react" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:target_kind, :string)
      field(:session_key, :string)
      field(:turn_ref, :string)
      field(:letter, :integer)
      # A document reacted on (kumbukumbu#61): its path and the hash of
      # the words it held then.
      field(:path, :string)
      field(:document_hash, :string)
      field(:emoji, :string)
      field(:by, :string)
      field(:reacted_at, :utc_datetime_usec)
      field(:told_at, :utc_datetime_usec)
      field(:told_in, :string)
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
      field(:instant_inferred, :boolean, default: false)
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
      field(:text, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule RetrievalUse do
    @moduledoc "One thing retrieval did with one target in a turn: considered, returned or used, and through what (the resident's work order, 2026-11-02)."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_retrieval_use" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:position, :integer, primary_key: true)
      field(:account_id, :binary_id)
      field(:session_key, :string)
      field(:turn_ref, :string)
      field(:target, :string)
      field(:stage, :string)
      field(:via, :string)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Bookmark do
    @moduledoc "A moment with a span (spec §6.3): the resident's line and summary, the anchor turn, the pin and the weight."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_bookmark" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:session_key, :string)
      field(:anchor_ref, :string)
      field(:anchor_at, :utc_datetime_usec)
      field(:turns_back, :integer, default: 1)
      field(:line, :string)
      field(:summary, :string)
      field(:added_by_kind, :string)
      field(:added_by_id, :string)
      field(:added_by_model, :string)
      field(:proposed_by_kind, :string)
      field(:proposed_by_id, :string)
      field(:pinned_by_kind, :string)
      field(:pinned_by_id, :string)
      field(:pinned_at, :utc_datetime_usec)
      field(:pin_evidences, :integer)
      field(:register, :string)
      field(:weight, :float, default: 1.0)
      # The timeline's weight (kumbukumbu#51), hers.
      field(:importance, :integer, default: 0)
      field(:status, :string)
      field(:weighed_at, :utc_datetime_usec)
      field(:last_indexed_at, :utc_datetime_usec)
      field(:last_recalled_at, :utc_datetime_usec)
      field(:created_at, :utc_datetime_usec)
      field(:tags, {:array, :string}, virtual: true, default: [])
      # Set on the witness's reads alone (kumbukumbu#62): the bookmark
      # was made in a private session she has not shared, and its words
      # are withheld.
      field(:private, :boolean, virtual: true, default: false)
    end

    @type t :: %__MODULE__{}
  end

  defmodule HouseLetter do
    @moduledoc "A letter between conversations of the resident (kumbukumbu#44), and which conversations have read it."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_house_letter" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:from_name, :string)
      field(:from_session, :string)
      field(:to_name, :string)
      field(:to_session, :string)
      field(:in_reply_to, :integer)
      field(:text, :string)
      field(:keepsake, :string)
      field(:link, :map)
      field(:by_kind, :string)
      field(:sent_at, :utc_datetime_usec)
      field(:read_by, {:array, :string}, default: [])
      field(:read_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Revision do
    @moduledoc "A correction to memory (F13): who made it, why, to what, and whether it holds, is proposed or was declined."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_revision" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:target_kind, :string)
      field(:target_id, :string)
      field(:kind, :string)
      field(:text, :string)
      field(:note, :string)
      field(:state, :string)
      field(:by_kind, :string)
      field(:by_id, :string)
      field(:at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
      field(:decision_note, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule BookmarkProposal do
    @moduledoc "The witness's proposed bookmark, open until the resident accepts or declines it."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_bookmark_proposal" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:ref, :string, primary_key: true)
      field(:session_key, :string)
      field(:anchor_ref, :string)
      field(:line, :string)
      field(:note, :string)
      field(:state, :string, default: "open")
      field(:proposed_by_kind, :string)
      field(:proposed_by_id, :string)
      field(:decided_note, :string)
      field(:bookmark_number, :integer)
      field(:proposed_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Tag do
    @moduledoc "One tag of the closed set: proposed, active or retired."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_tag" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:slug, :string, primary_key: true)
      field(:state, :string)
      field(:proposed_by_kind, :string)
      field(:proposed_by_id, :string)
      field(:note, :string)
      field(:created_at, :utc_datetime_usec)
      field(:decided_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Tagging do
    @moduledoc "A tag on a target of any record kind (spec §6.3)."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_tagging" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:tag, :string, primary_key: true)
      field(:target_kind, :string, primary_key: true)
      field(:target_id, :string, primary_key: true)
      field(:applied_by_kind, :string)
      field(:applied_by_id, :string)
      field(:applied_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "One session by key, under whatever scope the caller holds."
  @spec session(String.t()) :: Session.t() | nil
  def session(key), do: Repo.one(from(s in Session, where: s.key == ^key))

  @doc "The session of `adapter` with a turn started and not yet captured, newest first."
  @spec open_turn(String.t()) :: Session.t() | nil
  def open_turn(adapter),
    do:
      Repo.one(
        from(s in Session,
          where: s.adapter == ^adapter and not is_nil(s.open_turn_ref),
          order_by: [desc: s.last_turn_at, desc: s.opened_at],
          limit: 1
        )
      )

  @doc "Every session of `adapter` with a turn started and not yet captured, newest first (kumbukumbu#41)."
  @spec open_turns(String.t()) :: [Session.t()]
  def open_turns(adapter),
    do:
      Repo.all(
        from(s in Session,
          where: s.adapter == ^adapter and not is_nil(s.open_turn_ref),
          order_by: [desc: s.open_turn_at, desc: s.opened_at, asc: s.key]
        )
      )

  @doc """
  The sessions of `kinds` with a turn open or spoken in since `since`,
  in any order (kumbukumbu#42). Filtered here rather than over every
  session the resident ever had, because every turn reads it and the
  sessions only accumulate.
  """
  @spec open_since([String.t()], DateTime.t()) :: [Session.t()]
  def open_since(kinds, since) do
    Repo.all(
      from(s in Session,
        where:
          s.kind in ^kinds and
            (not is_nil(s.open_turn_ref) or s.last_turn_at >= ^since or
               (is_nil(s.last_turn_at) and s.opened_at >= ^since))
      )
    )
  end

  @doc "How many injections each turn of a session recorded, by turn ref: the inspector's counts."
  @spec drew_on(String.t()) :: %{String.t() => non_neg_integer()}
  def drew_on(key) do
    from(i in ContextInjection,
      where: i.session_key == ^key,
      group_by: i.turn_ref,
      select: {i.turn_ref, count(i.position)}
    )
    |> Repo.all()
    |> Map.new()
  end

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

  @doc """
  Each target retrieval has touched, with how many times it was
  considered, returned and used, and when it was last returned and last
  used; `kind` narrows to targets of one kind (`bookmark`), `target` to
  one. Counted across sessions under the scope, so the resident's read is
  everything and a witness's is the sessions they are party to.
  """
  @carried ~w(promised)

  @spec retrieval_counts(keyword()) :: [map()]
  def retrieval_counts(opts \\ []) do
    query =
      from(u in RetrievalUse,
        group_by: u.target,
        select: %{
          target: u.target,
          # A section loaded whole on every turn (`promised`, every open
          # commitment) was never chosen, so it is carried, not considered
          # or returned (kumbukumbu#52): counted apart, at the read, so
          # the turns recorded before the split read the same way.
          considered:
            filter(count(u.position), u.stage == "considered" and u.via not in @carried),
          returned: filter(count(u.position), u.stage == "returned" and u.via not in @carried),
          carried: filter(count(u.position), u.stage == "returned" and u.via in @carried),
          used: filter(count(u.position), u.stage == "used"),
          last_returned_at: filter(max(u.at), u.stage == "returned"),
          last_used_at: filter(max(u.at), u.stage == "used")
        }
      )

    query =
      case opts[:kind] do
        nil -> query
        kind -> from(u in query, where: like(u.target, ^"#{kind}/%"))
      end

    query =
      case opts[:target] do
        nil -> query
        target -> from(u in query, where: u.target == ^target)
      end

    Repo.all(query)
  end

  @doc "Every house letter, oldest first (kumbukumbu#44)."
  @spec house_letters() :: [HouseLetter.t()]
  def house_letters, do: Repo.all(from(l in HouseLetter, order_by: l.number))

  @doc """
  A page of a session's messages, in order: the last `limit` before the
  `{sequence, position}` cursor, or the last `limit` of all when the
  cursor is nil, and whether earlier ones remain. The chat reads the
  newest page first and pages back as the reader scrolls up, so a long
  conversation is never read whole to show its last screen.
  """
  @spec messages_page(String.t(), {integer(), integer()} | nil, pos_integer()) ::
          {[Message.t()], boolean()}
  def messages_page(key, before, limit) do
    rows =
      from(m in Message,
        where: m.session_key == ^key,
        order_by: [desc: m.sequence, desc: m.position],
        limit: ^(limit + 1)
      )
      |> before_cursor(before)
      |> Repo.all()

    {rows |> Enum.take(limit) |> Enum.reverse(), length(rows) > limit}
  end

  @doc """
  A page of a session's messages forward (kumbukumbu#57): the first
  `limit` after the `{sequence, position}` cursor, or the first `limit`
  of all when it is nil, in order, and whether later ones remain.
  """
  @spec messages_after(String.t(), {integer(), integer()} | nil, non_neg_integer()) ::
          {[Message.t()], boolean()}
  def messages_after(key, after_cursor, limit) do
    rows =
      from(m in Message,
        where: m.session_key == ^key,
        order_by: [asc: m.sequence, asc: m.position],
        limit: ^(limit + 1)
      )
      |> after_cursor(after_cursor)
      |> Repo.all()

    {Enum.take(rows, limit), length(rows) > limit}
  end

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, {sequence, position}),
    do:
      from(m in query,
        where: m.sequence > ^sequence or (m.sequence == ^sequence and m.position > ^position)
      )

  @doc """
  The message an anchor read centres on (kumbukumbu#57): the one at a
  `{sequence, position}` cursor, or the first message of a turn by its
  ref; nil when the session holds neither.
  """
  @spec anchor_message(String.t(), {:cursor, {integer(), integer()}} | {:turn, String.t()}) ::
          Message.t() | nil
  def anchor_message(key, {:cursor, {sequence, position}}),
    do:
      Repo.one(
        from(m in Message,
          where: m.session_key == ^key and m.sequence == ^sequence and m.position == ^position,
          limit: 1
        )
      )

  def anchor_message(key, {:turn, ref}),
    do:
      Repo.one(
        from(m in Message,
          where: m.session_key == ^key and m.turn_ref == ^ref,
          order_by: [asc: m.sequence, asc: m.position],
          limit: 1
        )
      )

  @doc """
  How many messages each local day holds (kumbukumbu#58): `{day, count}`
  for the resident's messages sent in `[from, to)`, the day the ISO date
  of the instant in `zone`, of one session when `key` is given. The
  scope decides which sessions are seen; the resident is named too, as an
  account's scope sees every resident it is party to.
  """
  @spec message_days(String.t(), String.t(), DateTime.t(), DateTime.t(), String.t() | nil) ::
          [{String.t(), non_neg_integer()}]
  def message_days(resident_id, zone, from, to, key) do
    query =
      from(m in Message,
        where: m.resident_id == ^resident_id and m.sent_at >= ^from and m.sent_at < ^to,
        group_by: selected_as(:day),
        select:
          {selected_as(
             fragment(
               "to_char((? AT TIME ZONE 'UTC') AT TIME ZONE ?, 'YYYY-MM-DD')",
               m.sent_at,
               ^zone
             ),
             :day
           ), count()}
      )

    query = if key, do: from(m in query, where: m.session_key == ^key), else: query
    Repo.all(query)
  end

  @doc "Per session and local day in `[from, to)`, its first and last message and how many (kumbukumbu#60): `{key, day, first, last, count}`, under the caller's scope."
  @spec session_days(String.t(), String.t(), DateTime.t(), DateTime.t()) :: [
          {String.t(), String.t(), DateTime.t(), DateTime.t(), non_neg_integer()}
        ]
  def session_days(resident_id, zone, from, to) do
    Repo.all(
      from(m in Message,
        where: m.resident_id == ^resident_id and m.sent_at >= ^from and m.sent_at < ^to,
        group_by: [m.session_key, selected_as(:day)],
        select:
          {m.session_key,
           selected_as(
             fragment(
               "to_char((? AT TIME ZONE 'UTC') AT TIME ZONE ?, 'YYYY-MM-DD')",
               m.sent_at,
               ^zone
             ),
             :day
           ), min(m.sent_at), max(m.sent_at), count()}
      )
    )
  end

  @doc "How many bookmarks each local day holds (kumbukumbu#58): by the moment's instant, its anchor's or else its making's, in `[from, to)`."
  @spec bookmark_days(String.t(), DateTime.t(), DateTime.t()) :: [{String.t(), non_neg_integer()}]
  def bookmark_days(zone, from, to) do
    Repo.all(
      from(b in Bookmark,
        where:
          coalesce(b.anchor_at, b.created_at) >= type(^from, :utc_datetime_usec) and
            coalesce(b.anchor_at, b.created_at) < type(^to, :utc_datetime_usec),
        group_by: selected_as(:day),
        select:
          {selected_as(
             fragment(
               "to_char((? AT TIME ZONE 'UTC') AT TIME ZONE ?, 'YYYY-MM-DD')",
               coalesce(b.anchor_at, b.created_at),
               ^zone
             ),
             :day
           ), count()}
      )
    )
  end

  defp before_cursor(query, nil), do: query

  defp before_cursor(query, {sequence, position}),
    do:
      from(m in query,
        where: m.sequence < ^sequence or (m.sequence == ^sequence and m.position < ^position)
      )

  @doc """
  The last `count` messages of a session since its compaction, in order:
  the live transcript the brain is shown. One statement, joined on the
  session's watermark, because the capture-cost test budgets this read
  and a second query for the watermark would spend it on a constant.
  """
  @spec recent_messages(String.t(), pos_integer()) :: [Message.t()]
  def recent_messages(key, count) do
    from(m in Message,
      join: s in Session,
      on: s.resident_id == m.resident_id and s.key == m.session_key,
      where: m.session_key == ^key and m.sequence > s.compacted_through,
      order_by: [desc: m.sequence, desc: m.position],
      limit: ^count
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc "The last `count` messages of a session, in order, whatever any compaction covered (brain#60)."
  @spec latest_messages(String.t(), pos_integer()) :: [Message.t()]
  def latest_messages(key, count) do
    from(m in Message,
      where: m.session_key == ^key,
      order_by: [desc: m.sequence, desc: m.position],
      limit: ^count
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc "How many of a session's messages were said before `at`: where a day begins, as transcript_read's `from`."
  @spec count_before(String.t(), DateTime.t()) :: non_neg_integer()
  def count_before(key, at),
    do:
      Repo.one(
        from(m in Message,
          where: m.session_key == ^key and m.sent_at < ^at,
          select: count(m.sequence)
        )
      )

  @doc "How many turns the resident's conversations of `kind` captured since `at` (sunna#34's floor)."
  @spec turns_since(String.t(), DateTime.t()) :: non_neg_integer()
  def turns_since(kind, at),
    do:
      Repo.one(
        from(m in Message,
          join: s in Session,
          on: s.resident_id == m.resident_id and s.key == m.session_key,
          where: s.kind == ^kind and m.sent_at >= ^at,
          select: count(m.turn_ref, :distinct)
        )
      )

  @doc "How many messages a session holds."
  @spec message_count(String.t()) :: non_neg_integer()
  def message_count(key),
    do: Repo.one(from(m in Message, where: m.session_key == ^key, select: count(m.sequence)))

  @doc "Every message sent in [from, to) across the resident's sessions but the imported ones, in order: the nightly pass's read."
  @spec messages_between(DateTime.t(), DateTime.t()) :: [Message.t()]
  # An imported session's messages are left out (kumbukumbu#37): they
  # carry their original instants, so a day the other platform already
  # judged would otherwise be judged again here, on its whole history.
  def messages_between(from, to) do
    imported = Conversation.imported()

    Repo.all(
      from(m in Message,
        join: s in Session,
        on: s.resident_id == m.resident_id and s.key == m.session_key,
        where: m.sent_at >= ^from and m.sent_at < ^to and s.kind != ^imported,
        order_by: [asc: m.sent_at, asc: m.sequence, asc: m.position]
      )
    )
  end

  @doc "How many messages of a session follow store sequence `after_sequence`: what compaction has not covered."
  @spec messages_after(String.t(), non_neg_integer()) :: non_neg_integer()
  def messages_after(key, after_sequence) do
    Repo.one(
      from(m in Message,
        where: m.session_key == ^key and m.sequence > ^after_sequence,
        select: count()
      )
    )
  end

  @doc "The messages of a turn, in order."
  @spec turn_messages(String.t()) :: [Message.t()]
  def turn_messages(turn_ref),
    do:
      Repo.all(
        from(m in Message,
          where: m.turn_ref == ^turn_ref,
          order_by: [asc: m.sequence, asc: m.position]
        )
      )

  @doc "Messages whose content holds `text`, newest first; unweighted, as spec §6.3 asks."
  @spec search(String.t(), pos_integer()) :: [Message.t()]
  def search(text, limit) do
    Repo.all(
      from(m in Message,
        where: ilike(m.content, ^search_pattern(text)) and m.role != "tool",
        order_by: [desc: m.sequence, desc: m.position],
        limit: ^limit
      )
    )
  end

  @doc "The same, within the sessions named (the room, spec §6.3 P23)."
  @spec search(String.t(), pos_integer(), [String.t()]) :: [Message.t()]
  def search(text, limit, keys) when is_list(keys) do
    Repo.all(
      from(m in Message,
        where:
          ilike(m.content, ^search_pattern(text)) and m.session_key in ^keys and
            m.role != "tool",
        order_by: [desc: m.sequence, desc: m.position],
        limit: ^limit
      )
    )
  end

  @doc """
  One resident's messages holding `text`, newest first and unweighted
  (spec §6.3), each with its session: the one search's words
  (kumbukumbu#59). A private, unshared session's messages are left out
  here as well as by the policy, which keys them away from the account
  (#28), so a scope that reads them still never lists them.
  """
  @spec search_words(String.t(), String.t(), pos_integer()) :: [{Message.t(), Session.t()}]
  def search_words(resident_id, text, limit) do
    Repo.all(
      from(m in Message,
        join: s in Session,
        on: s.resident_id == m.resident_id and s.key == m.session_key,
        where:
          m.resident_id == ^resident_id and ilike(m.content, ^search_pattern(text)) and
            m.role != "tool" and (s.private == false or s.shared == true),
        order_by: [desc: m.sequence, desc: m.position],
        limit: ^limit,
        select: {m, s}
      )
    )
  end

  defp search_pattern(text), do: "%" <> String.replace(text, ~r/[%_\\]/, &("\\" <> &1)) <> "%"

  @doc "The open capture failures the scope sees, oldest first."
  @spec open_failures() :: [CaptureFailure.t()]
  def open_failures,
    do: Repo.all(from(f in CaptureFailure, where: is_nil(f.resolved_at), order_by: f.failed_at))

  @doc "How many turns carried a section by this label, and the last time (brain#68's audit)."
  def shown(label) do
    Repo.one(
      from(i in ContextInjection,
        where: i.label == ^label,
        select: {count(i.turn_ref, :distinct), max(i.at)}
      )
    )
  end

  @doc "What a turn drew on, in the order it was injected."
  @spec injections(String.t()) :: [ContextInjection.t()]
  def injections(turn_ref),
    do:
      Repo.all(from(i in ContextInjection, where: i.turn_ref == ^turn_ref, order_by: i.position))

  # ---- memory ----

  defmodule Edge do
    @moduledoc "A learned retrieval edge (kumbukumbu#46): when `from` is in play, how worth bringing `to` is, as a deviation from neutral last touched at `touched_at`."
    use Ecto.Schema

    @primary_key false
    schema "kumbukumbu_edge" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:from_number, :integer, primary_key: true)
      field(:to_number, :integer, primary_key: true)
      field(:w, :float)
      field(:touched_at, :utc_datetime_usec)
      # The source's seed count at the last touch (kumbukumbu#53).
      field(:touched_count, :integer, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule EdgeSource do
    @moduledoc "How many turns a bookmark has been the seed of (kumbukumbu#53): the clock its outgoing edges decay by."
    use Ecto.Schema

    @primary_key false
    schema "kumbukumbu_edge_source" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:seeded, :integer, default: 0)
    end

    @type t :: %__MODULE__{}
  end

  defmodule CitationEdge do
    @moduledoc "One citation's contribution to an edge (kumbukumbu#53), by the source that made it, so removing the citation removes exactly it."
    use Ecto.Schema

    @primary_key false
    schema "kumbukumbu_citation_edge" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:source, :string, primary_key: true)
      field(:from_number, :integer, primary_key: true)
      field(:to_number, :integer, primary_key: true)
      field(:w, :float)
    end

    @type t :: %__MODULE__{}
  end

  defmodule EdgeTurn do
    @moduledoc "What a turn returned and what was seen used, until its feedback teaches the use rules once (kumbukumbu#46)."
    use Ecto.Schema

    @primary_key false
    schema "kumbukumbu_edge_turn" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:turn_ref, :string, primary_key: true)
      field(:returned, {:array, :integer}, default: [])
      field(:used, {:array, :integer}, default: [])
      field(:indexed, :boolean, default: false)
      field(:feedback, :boolean, default: false)
      field(:learned_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The learned edges out of `froms`, as stored (undecayed)."
  @spec edges_from([pos_integer()]) :: [Edge.t()]
  def edges_from([]), do: []

  def edges_from(froms) do
    Repo.all(
      from(e in Edge,
        left_join: s in EdgeSource,
        on: s.resident_id == e.resident_id and s.number == e.from_number,
        where: e.from_number in ^froms,
        select: %{
          from_number: e.from_number,
          to_number: e.to_number,
          w: e.w,
          touched_count: e.touched_count,
          seeded: coalesce(s.seeded, 0)
        }
      )
    )
  end

  @doc "The citations' contributions out of these bookmarks, summed by edge (kumbukumbu#53)."
  def citation_edges_from([]), do: []

  def citation_edges_from(froms) do
    Repo.all(
      from(c in CitationEdge,
        where: c.from_number in ^froms,
        group_by: [c.from_number, c.to_number],
        select: %{from_number: c.from_number, to_number: c.to_number, w: sum(c.w)}
      )
    )
  end

  defmodule Vector do
    @moduledoc "One row of the madeleine's index (spec §6.3, P10): a bookmark's words, or the limits, embedded; derived, rebuilt from the rows."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_vector" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:kind, :string, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:text, :string)
      field(:hash, :string)
      field(:model, :string)
      field(:embedding, Pgvector.Ecto.Vector)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Passage do
    @moduledoc "One passage of a captured message, embedded (kumbukumbu#49): the transcripts by meaning; derived, rebuilt from the messages."
    use Ecto.Schema
    @primary_key false
    schema "kumbukumbu_passage" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:session_key, :string, primary_key: true)
      field(:sent_at, :utc_datetime_usec, primary_key: true)
      field(:hash, :string, primary_key: true)
      field(:part, :integer, primary_key: true)
      field(:turn_ref, :string)
      field(:role, :string)
      field(:text, :string)
      field(:model, :string)
      field(:embedding, Pgvector.Ecto.Vector)
      field(:at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The oldest messages with words that have no passages yet: the user's and the resident's, never a tool's or a note."
  @spec unembedded_messages(pos_integer()) :: [Message.t()]
  def unembedded_messages(limit) do
    Repo.all(
      from(m in Message,
        left_join: p in Passage,
        on:
          p.resident_id == m.resident_id and p.session_key == m.session_key and
            p.sent_at == m.sent_at and p.hash == m.hash and p.part == 0,
        where: is_nil(p.hash) and m.role in ["user", "assistant"] and m.content != "",
        order_by: [asc: m.sent_at],
        limit: ^limit
      )
    )
  end

  @doc "Puts passages, a message's parts at once."
  def put_passages([]), do: :ok

  def put_passages(rows) do
    rows
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Passage, chunk,
        on_conflict: {:replace, [:text, :model, :embedding, :at]},
        conflict_target: [:resident_id, :session_key, :sent_at, :hash, :part]
      )
    end)
  end

  @doc "The passages nearest a vector among the sessions named, nearest first."
  def nearest_passages(vector, keys, limit) when is_list(keys) do
    Repo.all(
      from(p in Passage,
        where: p.session_key in ^keys,
        order_by: cosine_distance(p.embedding, ^vector),
        limit: ^limit,
        select: %{
          session_key: p.session_key,
          turn_ref: p.turn_ref,
          sent_at: p.sent_at,
          role: p.role,
          text: p.text,
          distance: cosine_distance(p.embedding, ^vector)
        }
      )
    )
  end

  @doc "The madeleine's rows, by kind and number."
  @spec vectors() :: [Vector.t()]
  def vectors, do: Repo.all(from(v in Vector, order_by: [v.kind, v.number]))

  @doc "One row of the madeleine's index."
  def vector(kind, number),
    do: Repo.one(from(v in Vector, where: v.kind == ^kind and v.number == ^number))

  @doc "Writes rows, replacing any with the same kind and number."
  def put_vectors([]), do: :ok

  def put_vectors(rows) do
    Repo.insert_all(Vector, rows,
      on_conflict: {:replace, [:text, :hash, :model, :embedding, :at]},
      conflict_target: [:resident_id, :kind, :number]
    )

    :ok
  end

  @doc "Drops rows by kind and number."
  def delete_vectors([]), do: :ok

  def delete_vectors(keys) do
    Enum.each(keys, fn {kind, number} ->
      Repo.delete_all(from(v in Vector, where: v.kind == ^kind and v.number == ^number))
    end)

    :ok
  end

  @doc "The nearest rows of a kind to a vector, nearest first, each with its cosine distance and its own embedding."
  def nearest_vectors(vector, kind, limit) do
    Repo.all(
      from(v in Vector,
        where: v.kind == ^kind,
        order_by: cosine_distance(v.embedding, ^vector),
        limit: ^limit,
        select: %{
          number: v.number,
          text: v.text,
          embedding: v.embedding,
          distance: cosine_distance(v.embedding, ^vector)
        }
      )
    )
  end

  @doc "The resident's bookmarks, newest first, each with its tags."
  @spec bookmarks() :: [Bookmark.t()]
  def bookmarks do
    Bookmark |> from(order_by: [desc: :number]) |> Repo.all() |> with_tags()
  end

  @doc """
  A page of the resident's bookmarks, newest first by number (kumbukumbu
  #57): the first `limit` below `before` (nil for the newest) whose moment,
  its anchor's instant or else its making's, falls in `[from, to)` (either
  nil for open), each with its tags, and whether more remain.
  """
  @spec bookmarks_page(
          pos_integer() | nil,
          pos_integer(),
          DateTime.t() | nil,
          DateTime.t() | nil
        ) :: {[Bookmark.t()], boolean()}
  def bookmarks_page(before, limit, from, to) do
    query = from(b in Bookmark, order_by: [desc: b.number], limit: ^(limit + 1))
    query = if before, do: from(b in query, where: b.number < ^before), else: query

    query =
      if from,
        do:
          from(b in query,
            where: coalesce(b.anchor_at, b.created_at) >= type(^from, :utc_datetime_usec)
          ),
        else: query

    query =
      if to,
        do:
          from(b in query,
            where: coalesce(b.anchor_at, b.created_at) < type(^to, :utc_datetime_usec)
          ),
        else: query

    rows = Repo.all(query)
    {rows |> Enum.take(limit) |> with_tags(), length(rows) > limit}
  end

  @doc "The timeline's bookmarks (kumbukumbu#51): pinned, or weighed 2 and up; oldest first by when the moment was."
  def timeline_bookmarks do
    Repo.all(
      from(b in Bookmark,
        where: not is_nil(b.pinned_at) or b.importance >= 2,
        order_by: [asc: coalesce(b.anchor_at, b.created_at), asc: b.number],
        select: %{
          number: b.number,
          line: b.line,
          at: coalesce(b.anchor_at, b.created_at),
          pinned: not is_nil(b.pinned_at),
          importance: b.importance,
          status: b.status,
          weighed_at: b.weighed_at
        }
      )
    )
  end

  @doc "One bookmark by number, with its tags."
  @spec bookmark(pos_integer()) :: Bookmark.t() | nil
  def bookmark(number) do
    case Repo.one(from(b in Bookmark, where: b.number == ^number)) do
      nil -> nil
      row -> row |> List.wrap() |> with_tags() |> hd()
    end
  end

  @doc "The open bookmark proposals, oldest first."
  @spec open_proposals() :: [BookmarkProposal.t()]
  def open_proposals,
    do:
      Repo.all(
        from(p in BookmarkProposal, where: p.state == "open", order_by: [asc: p.proposed_at])
      )

  @doc "The bookmark proposals in `states` (open, accepted, declined), oldest first (kumbukumbu#63)."
  @spec proposals_in([String.t()]) :: [BookmarkProposal.t()]
  def proposals_in(states) when is_list(states),
    do:
      Repo.all(
        from(p in BookmarkProposal, where: p.state in ^states, order_by: [asc: p.proposed_at])
      )

  @doc "The keys of the private sessions she has not shared (kumbukumbu#28)."
  @spec locked_keys() :: [String.t()]
  def locked_keys,
    do: Repo.all(from(s in Session, where: s.private and not s.shared, select: s.key))

  @doc "The tag set, every state, by slug."
  @spec tags() :: [Tag.t()]
  def tags, do: Repo.all(from(t in Tag, order_by: [asc: t.slug]))

  @doc "The taggings on one target."
  @spec taggings(String.t(), String.t()) :: [Tagging.t()]
  def taggings(kind, id),
    do:
      Repo.all(
        from(t in Tagging,
          where: t.target_kind == ^kind and t.target_id == ^id,
          order_by: [asc: t.tag]
        )
      )

  @doc "Everything carrying a tag: one query across every record kind (spec §6.3)."
  @spec tagged(String.t()) :: [Tagging.t()]
  def tagged(slug),
    do:
      Repo.all(
        from(t in Tagging,
          where: t.tag == ^slug,
          order_by: [asc: t.target_kind, asc: t.target_id]
        )
      )

  # One query for the tags of a set of bookmarks rather than one per row.
  defp with_tags([]), do: []

  defp with_tags(rows) do
    ids = Enum.map(rows, &Integer.to_string(&1.number))

    tags =
      from(t in Tagging,
        where: t.target_kind == "bookmark" and t.target_id in ^ids,
        select: {t.target_id, t.tag}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.map(rows, fn b ->
      %{b | tags: tags |> Map.get(Integer.to_string(b.number), []) |> Enum.sort()}
    end)
  end

  # ---- revisions ----

  @doc "Every revision, newest first."
  def revisions, do: Repo.all(from(r in Revision, order_by: [desc: r.number]))

  @doc "The revisions on one target, applied and proposed, in order."
  def revisions_of(kind, target_id) do
    Repo.all(
      from(r in Revision,
        where: r.target_kind == ^kind and r.target_id == ^target_id and r.state != "declined",
        order_by: r.number
      )
    )
  end

  @doc "The reacts, oldest first; `untold: true` for those not yet told her (kumbukumbu#56), `path:` for one document's (#61)."
  @spec reacts(keyword()) :: [React.t()]
  def reacts(opts \\ []) do
    q = from(r in React, order_by: r.number)
    q = if opts[:untold], do: from(r in q, where: is_nil(r.told_at)), else: q

    q =
      if opts[:session_key],
        do: from(r in q, where: r.session_key == ^opts[:session_key]),
        else: q

    q = if opts[:by], do: from(r in q, where: r.by == ^opts[:by]), else: q
    q = if opts[:path], do: from(r in q, where: r.path == ^opts[:path]), else: q
    Repo.all(q)
  end

  @doc "Whether a session holds a message of `role` in the turn named: hers is `assistant`, his `user` (kumbukumbu#56)."
  @spec message?(String.t(), String.t(), String.t()) :: boolean()
  def message?(session_key, turn_ref, role),
    do:
      Repo.exists?(
        from(m in Message,
          where: m.session_key == ^session_key and m.turn_ref == ^turn_ref and m.role == ^role
        )
      )

  @doc "Whether a house letter of that number exists (kumbukumbu#56)."
  @spec letter?(integer()) :: boolean()
  def letter?(number), do: Repo.exists?(from(l in HouseLetter, where: l.number == ^number))
end
