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
      field(:shared, :boolean, default: false)
      field(:private, :boolean, default: false)
      field(:opened_at, :utc_datetime_usec)
      field(:last_turn_at, :utc_datetime_usec)
      field(:turns, :integer, default: 0)
      field(:summary, :string)
      field(:compacted_through, :integer, default: 0)
      field(:open_turn_ref, :string)
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
      field(:text, :string)
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
      field(:last_indexed_at, :utc_datetime_usec)
      field(:last_recalled_at, :utc_datetime_usec)
      field(:created_at, :utc_datetime_usec)
      field(:tags, {:array, :string}, virtual: true, default: [])
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

  @doc "Every message sent in [from, to) across the resident's sessions but the imported ones, in order: the nightly pass's read."
  @spec messages_between(DateTime.t(), DateTime.t()) :: [Message.t()]
  # An imported session's messages are left out (kumbukumbu #37): they
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
        where: ilike(m.content, ^search_pattern(text)),
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
        where: ilike(m.content, ^search_pattern(text)) and m.session_key in ^keys,
        order_by: [desc: m.sequence, desc: m.position],
        limit: ^limit
      )
    )
  end

  defp search_pattern(text), do: "%" <> String.replace(text, ~r/[%_\\]/, &("\\" <> &1)) <> "%"

  @doc "The open capture failures the scope sees, oldest first."
  @spec open_failures() :: [CaptureFailure.t()]
  def open_failures,
    do: Repo.all(from(f in CaptureFailure, where: is_nil(f.resolved_at), order_by: f.failed_at))

  @doc "What a turn drew on, in the order it was injected."
  @spec injections(String.t()) :: [ContextInjection.t()]
  def injections(turn_ref),
    do:
      Repo.all(from(i in ContextInjection, where: i.turn_ref == ^turn_ref, order_by: i.position))

  # ---- memory ----

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
end
