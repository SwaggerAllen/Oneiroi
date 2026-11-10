defmodule Oneiroi.Seshat.Store do
  @moduledoc """
  The library's rows and their queries, under the resident's scope. The
  document rows are projected from the stream (their identity and
  provenance) and completed by the index (hash, title, status, the model
  they were embedded with); the chunks, references and runs are derived
  by the index alone (spec §3.2: neither store nor event; an index run
  over files).
  """
  import Ecto.Query, only: [from: 2]
  import Pgvector.Ecto.Query, only: [cosine_distance: 2]

  alias Oneiroi.Repo

  defmodule Document do
    @moduledoc "A registered document: its kind from its path, its provenance, and what the index last read of it."
    use Ecto.Schema
    @primary_key false
    schema "seshat_document" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:path, :string, primary_key: true)
      field(:kind, :string)
      field(:origin, :string)
      field(:title, :string)
      field(:status, :string)
      field(:hash, :string)
      field(:bytes, :integer)
      field(:versions, :integer, default: 0)
      field(:embedded_with, :string)
      field(:chunks, :integer, default: 0)
      field(:indexed_at, :utc_datetime_usec)
      field(:missing_at, :utc_datetime_usec)
      field(:registered_at, :utc_datetime_usec)
      field(:written_at, :utc_datetime_usec)
      field(:written_by_kind, :string)
      field(:published_url, :string)
      field(:published_at, :utc_datetime_usec)
      field(:source_repo, :string)
      field(:source_commit, :string)
      field(:source_path, :string)
      field(:source_blob, :string)
      field(:note, :string)
      field(:noted_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule UserKind do
    @moduledoc "A kind of the resident's own (seshat#51): its descriptor, the folder's file projected, and who made and last changed it."
    use Ecto.Schema
    @primary_key false
    schema "seshat_user_kind" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:kind, :string, primary_key: true)
      field(:descriptor, :map)
      field(:created_by, :string)
      field(:updated_by, :string)
      field(:created_at, :utc_datetime_usec)
      field(:updated_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule KindGate do
    @moduledoc "A system kind's approval gate as it stands for the resident (seshat#51), where it moved from the platform's."
    use Ecto.Schema
    @primary_key false
    schema "seshat_kind_gate" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:kind, :string, primary_key: true)
      field(:approvable, :boolean)
      field(:moved_by, :string)
      field(:moved_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule KindGateProposal do
    @moduledoc "A proposal to turn a system kind's gate off (seshat#51), and the other party's answer."
    use Ecto.Schema
    @primary_key false
    schema "seshat_kind_gate_proposal" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:kind, :string)
      field(:approvable, :boolean)
      field(:proposed_by, :string)
      field(:note, :string)
      field(:proposed_at, :utc_datetime_usec)
      field(:agree, :boolean)
      field(:answered_by, :string)
      field(:answer_note, :string)
      field(:answered_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule PieceReview do
    @moduledoc "A writing piece's review (seshat#42): approved, declined or drafted, the note, the version, the Substack draft."
    use Ecto.Schema
    @primary_key false
    schema "seshat_piece_review" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:path, :string, primary_key: true)
      field(:state, :string)
      field(:note, :string)
      field(:hash, :string)
      field(:decided_at, :utc_datetime_usec)
      field(:draft_url, :string)
      field(:drafted_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Digest do
    @moduledoc "A digest asked of the reader (seshat#40): since when, by whom, and how it settled."
    use Ecto.Schema
    @primary_key false
    schema "seshat_digest" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:session_key, :string)
      field(:since, :utc_datetime_usec)
      field(:asked_by, :string)
      field(:status, :string)
      field(:path, :string)
      field(:items, :integer)
      field(:reason, :string)
      field(:asked_at, :utc_datetime_usec)
      field(:settled_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule DocumentMove do
    @moduledoc "Where a document moved from and to (seshat#39): a citation of the old path follows it."
    use Ecto.Schema
    @primary_key false
    schema "seshat_document_move" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:from_path, :string, primary_key: true)
      field(:to_path, :string)
      field(:moved_at, :utc_datetime_usec)
      field(:moved_by_kind, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Chunk do
    @moduledoc "One chunk of a document with its vector."
    use Ecto.Schema
    @primary_key false
    schema "seshat_chunk" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:path, :string, primary_key: true)
      field(:ordinal, :integer, primary_key: true)
      field(:text, :string)
      field(:embedding, Pgvector.Ecto.Vector)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Reference do
    @moduledoc "A citation edge from a document to a target, resolved when read."
    use Ecto.Schema
    @primary_key false
    schema "seshat_reference" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:from_path, :string, primary_key: true)
      field(:ordinal, :integer, primary_key: true)
      field(:from_kind, :string)
      field(:target, :string)
      field(:slug, :string)
      field(:kind, :string)
      field(:ref, :string)
      field(:resolved, :boolean)
      field(:reason, :string)
      field(:label, :string)
      field(:resolved_at, :utc_datetime_usec)
      field(:checked_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule IndexRun do
    @moduledoc "One index run: what it scanned, embedded and found missing, or why it failed."
    use Ecto.Schema
    @primary_key false
    schema "seshat_index_run" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:id, :binary_id, primary_key: true)
      field(:sequence, :integer, read_after_writes: true)
      field(:at, :utc_datetime_usec)
      field(:outcome, :string)
      field(:reason, :string)
      field(:model, :string)
      field(:scanned, :integer, default: 0)
      field(:embedded, :integer, default: 0)
      field(:chunks, :integer, default: 0)
      field(:missing, :integer, default: 0)
      field(:by_kind, :string)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Oracle do
    @moduledoc "One question put to the oracle (seshat#34): what, of which sources, by whom, and how it settled."
    use Ecto.Schema

    @primary_key false
    schema "seshat_oracle" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:question, :string)
      field(:sources, {:array, :string}, default: [])
      field(:read, {:array, :string}, default: [])
      field(:used, {:array, :string}, default: [])
      field(:session_key, :string)
      field(:asked_by, :string)
      field(:status, :string)
      field(:path, :string)
      field(:confidence, :string)
      field(:model, :string)
      field(:reason, :string)
      field(:dispatched_at, :utc_datetime_usec)
      field(:settled_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Research do
    @moduledoc "One question for the reader's research pass (seshat#38): what, from which pages, by whom, and how it settled."
    use Ecto.Schema

    @primary_key false
    schema "seshat_research" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:question, :string)
      field(:urls, {:array, :string}, default: [])
      field(:sources, {:array, :string}, default: [])
      field(:session_key, :string)
      field(:asked_by, :string)
      field(:status, :string)
      field(:path, :string)
      field(:reason, :string)
      field(:asked_at, :utc_datetime_usec)
      field(:settled_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule External do
    @moduledoc "A source outside the house, commissioned for citing (seshat#46): what it is, where it is fetched from, and its latest copy."
    use Ecto.Schema

    @primary_key false
    schema "seshat_external" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:kind, :string)
      field(:key, :string)
      field(:url, :string)
      field(:ref, :string)
      field(:title, :string)
      field(:status, :string)
      field(:path, :string)
      field(:content_hash, :string)
      field(:previous_hash, :string)
      field(:commit, :string)
      field(:bytes, :integer)
      field(:fetches, :integer, default: 0)
      field(:reason, :string)
      field(:session_key, :string)
      field(:commissioned_by, :string)
      field(:commissioned_at, :utc_datetime_usec)
      field(:asked_at, :utc_datetime_usec)
      field(:fetched_at, :utc_datetime_usec)
      field(:previous_fetched_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  @doc "The external sources, newest first; `status:` narrows to asked, fetched or failed."
  def externals(opts \\ []) do
    query =
      from(x in External, order_by: [desc: x.number], limit: ^Keyword.get(opts, :limit, 200))

    case Keyword.get(opts, :status) do
      nil -> Repo.all(query)
      status -> Repo.all(from(x in query, where: x.status == ^status))
    end
  end

  def external(number), do: Repo.one(from(x in External, where: x.number == ^number))
  def external_by_key(key), do: Repo.one(from(x in External, where: x.key == ^key))

  @doc "The research questions, newest first; `status:` narrows to open, answered or failed."
  @spec researches(keyword()) :: [Research.t()]
  def researches(opts \\ []) do
    query = from(r in Research, order_by: [desc: r.number], limit: ^Keyword.get(opts, :limit, 50))

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from(r in query, where: r.status == ^status)
      end

    Repo.all(query)
  end

  @doc "One research question by number, or nil."
  @spec research(pos_integer()) :: Research.t() | nil
  def research(number), do: Repo.one(from(r in Research, where: r.number == ^number))

  @doc """
  The oracle's questions, newest first, narrowed deliberately: `source:`
  one it read (a ref, exactly), `status:` open, answered or failed,
  `asked_by:` resident or witness, `q:` words in the question.
  """
  @spec oracles(keyword()) :: [Oracle.t()]
  def oracles(opts) do
    query = from(o in Oracle, order_by: [desc: o.number])

    query =
      Enum.reduce(opts, query, fn
        {:source, source}, q when is_binary(source) ->
          from(o in q, where: ^source in o.sources)

        {:read, ref}, q when is_binary(ref) ->
          from(o in q, where: ^ref in o.read)

        {:used, ref}, q when is_binary(ref) ->
          from(o in q, where: ^ref in o.used)

        {:status, status}, q when is_binary(status) ->
          from(o in q, where: o.status == ^status)

        {:asked_by, by}, q when is_binary(by) ->
          from(o in q, where: o.asked_by == ^by)

        {:q, words}, q when is_binary(words) ->
          from(o in q, where: ilike(o.question, ^"%#{escape(words)}%"))

        {:limit, n}, q when is_integer(n) ->
          from(o in q, limit: ^n)

        _other, q ->
          q
      end)

    Repo.all(query)
  end

  @doc "One oracle question by its number, or nil."
  @spec oracle(pos_integer()) :: Oracle.t() | nil
  def oracle(number), do: Repo.one(from(o in Oracle, where: o.number == ^number))

  defp escape(words), do: String.replace(words, ~r/[%_\\]/, &("\\" <> &1))

  defmodule Discussion do
    @moduledoc "A session linked to a piece."
    use Ecto.Schema
    @primary_key false
    schema "seshat_discussion" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:path, :string, primary_key: true)
      field(:session_key, :string, primary_key: true)
      field(:opened_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule JournalEntry do
    @moduledoc "One journal row: a day, its number within the day, a kind and the text (F29)."
    use Ecto.Schema
    @primary_key false
    schema "seshat_journal_entry" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:day, :string, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:kind, :string)
      field(:text, :string)
      field(:at, :utc_datetime_usec)
      field(:actor_kind, :string)
      field(:register, :string)
      field(:summary, :string)
      field(:done_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule Scene do
    @moduledoc "One row of a day's scenes (seshat#52): a scene, or a correction of one's summary (`kind`, `corrects`)."
    use Ecto.Schema
    @primary_key false
    schema "seshat_scene" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:day, :string, primary_key: true)
      field(:number, :integer, primary_key: true)
      field(:kind, :string)
      field(:corrects, :integer)
      field(:title, :string)
      field(:from_turn, :string)
      field(:to_turn, :string)
      field(:from_time, :utc_datetime_usec)
      field(:to_time, :utc_datetime_usec)
      field(:summary, :string)
      field(:mood, :string)
      field(:mood_was, :string)
      field(:mood_corrected_at, :utc_datetime_usec)
      field(:rounds_ran_out, :boolean, default: false)
      field(:register, :string)
      field(:at, :utc_datetime_usec)
      field(:actor_kind, :string)
      field(:corrected_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  defmodule SceneDay do
    @moduledoc "A day that has scenes (seshat#52), and whether the pass closed it."
    use Ecto.Schema
    @primary_key false
    schema "seshat_scene_day" do
      field(:resident_id, :binary_id, primary_key: true)
      field(:day, :string, primary_key: true)
      field(:complete, :boolean, default: false)
      field(:closed_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  # ---- the scenes (seshat#52) ----

  @doc "A day's scene rows in order."
  def scenes(day),
    do: Repo.all(from(s in Scene, where: s.day == ^day, order_by: s.number))

  @doc "The day rows in `[from, to]` (ISO dates, either nil for open), oldest first."
  def scene_days(from, to) do
    query = from(d in SceneDay, order_by: d.day)
    query = if from, do: from(d in query, where: d.day >= ^from), else: query
    query = if to, do: from(d in query, where: d.day <= ^to), else: query
    Repo.all(query)
  end

  @doc "The scene rows of the days in `[from, to]`, by day and number."
  def scenes_between(from, to) do
    query = from(s in Scene, order_by: [s.day, s.number])
    query = if from, do: from(s in query, where: s.day >= ^from), else: query
    query = if to, do: from(s in query, where: s.day <= ^to), else: query
    Repo.all(query)
  end

  @doc "How many scenes (never their corrections) each day in `[from, to]` holds."
  def scene_counts(from, to) do
    Repo.all(
      from(s in Scene,
        where: s.kind == "scene" and s.day >= ^from and s.day <= ^to,
        group_by: s.day,
        select: {s.day, count(s.number)}
      )
    )
  end

  @doc "A day's row, or nil."
  def scene_day(day), do: Repo.one(from(d in SceneDay, where: d.day == ^day))

  # ---- the journal ----

  @doc "The entries written since an instant, oldest first."
  def journal_entries_since(since),
    do: Repo.all(from(j in JournalEntry, where: j.at >= ^since, order_by: [j.at, j.number]))

  def journal_entries(day),
    do: Repo.all(from(j in JournalEntry, where: j.day == ^day, order_by: j.number))

  @doc "Per day, how many entries of each kind and how many todos are done, for the listed days in one statement."
  def journal_counts(days) do
    Repo.all(
      from(j in JournalEntry,
        where: j.day in ^days,
        group_by: [j.day, j.kind],
        select: {j.day, j.kind, count(j.number), count(j.done_at)}
      )
    )
    |> Enum.reduce(%{}, fn {day, kind, n, done}, acc ->
      acc
      |> Map.update(day, %{kind => n}, &Map.put(&1, kind, n))
      |> update_in([day], &Map.update(&1, "done", done, fn d -> d + done end))
    end)
  end

  # ---- documents ----

  @spec documents() :: [Document.t()]
  def documents, do: Repo.all(from(d in Document, order_by: [d.kind, d.path]))

  @spec document(String.t()) :: Document.t() | nil
  def document(path), do: Repo.one(from(d in Document, where: d.path == ^path))

  @doc "The digests, newest first; `status:` narrows."
  def digests(opts \\ []) do
    query = from(d in Digest, order_by: [desc: d.number])

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from(d in query, where: d.status == ^status)
      end

    Repo.all(query)
  end

  @doc "One digest by number, or nil."
  def digest(number), do: Repo.one(from(d in Digest, where: d.number == ^number))

  @doc "Where a path moved to, following moves to the last (seshat#39); nil if it never moved. A chain is at most as long as the moves, and a cycle stops at the path it began from."
  def moved_to(path, seen \\ MapSet.new()) do
    case Repo.one(from(m in DocumentMove, where: m.from_path == ^path, select: m.to_path)) do
      nil ->
        nil

      to ->
        if MapSet.member?(seen, to),
          do: to,
          else: moved_to(to, MapSet.put(seen, path)) || to
    end
  end

  @doc "Completes a document row with what the index read of it."
  def update_document(path, fields) when is_list(fields) do
    Repo.update_all(from(d in Document, where: d.path == ^path), set: fields)
    :ok
  end

  # ---- chunks ----

  def any_chunks?, do: Repo.exists?(Chunk)

  @doc "Replaces a document's chunks: a delete and one insert, or the delete alone when there are none."
  def replace_chunks(path, rows) do
    Repo.delete_all(from(c in Chunk, where: c.path == ^path))
    if rows != [], do: Repo.insert_all(Chunk, rows)
    :ok
  end

  @doc "The nearest chunks to a vector, with their documents, nearest first."
  def nearest(vector, limit) do
    Repo.all(
      from(c in Chunk,
        join: d in Document,
        on: d.resident_id == c.resident_id and d.path == c.path,
        order_by: cosine_distance(c.embedding, ^vector),
        limit: ^limit,
        select: %{
          path: c.path,
          ordinal: c.ordinal,
          text: c.text,
          kind: d.kind,
          title: d.title,
          status: d.status,
          source_repo: d.source_repo,
          source_commit: d.source_commit,
          source_path: d.source_path,
          distance: cosine_distance(c.embedding, ^vector)
        }
      )
    )
  end

  # ---- references ----

  def references(path),
    do: Repo.all(from(r in Reference, where: r.from_path == ^path, order_by: r.ordinal))

  def cited_by(target),
    do:
      Repo.all(
        from(r in Reference, where: r.target == ^target, order_by: [r.from_path, r.ordinal])
      )

  @doc "Every reference that resolved at least once, for the drift read."
  def once_resolved do
    Repo.all(
      from(r in Reference, where: not is_nil(r.resolved_at), order_by: [r.from_path, r.ordinal])
    )
  end

  def replace_references(path, rows) do
    Repo.delete_all(from(r in Reference, where: r.from_path == ^path))
    if rows != [], do: Repo.insert_all(Reference, rows)
    :ok
  end

  @doc "Each document's citations of the resident's own bookmarks, path => numbers (kumbukumbu#53)."
  def bookmark_citations(slug) do
    from(r in Reference,
      where: r.kind == "bookmark" and r.slug == ^slug,
      select: {r.from_path, r.ref}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {path, ref} ->
      case Integer.parse(ref) do
        {n, ""} when n > 0 -> [{path, n}]
        _other -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Deletes every edge minted from the kinds that never mint (spec §6.5), on every run."
  def delete_references_of_kinds(kinds) when is_list(kinds) do
    Repo.delete_all(from(r in Reference, where: r.from_kind in ^kinds))
    :ok
  end

  @doc "Marks a reference with what resolving it found now; `resolved_at` is kept from the first time it resolved."
  def mark_reference(path, ordinal, resolved?, label, reason, now) do
    set = [resolved: resolved?, label: label, reason: reason, checked_at: now]

    Repo.update_all(
      from(r in Reference, where: r.from_path == ^path and r.ordinal == ^ordinal),
      set: set
    )

    if resolved? do
      Repo.update_all(
        from(r in Reference,
          where: r.from_path == ^path and r.ordinal == ^ordinal and is_nil(r.resolved_at)
        ),
        set: [resolved_at: now]
      )
    end

    :ok
  end

  # ---- runs ----

  def insert_run(%IndexRun{} = run) do
    Repo.insert!(run)
    :ok
  end

  # Newest first by the table's own sequence, never the instant: two runs
  # in one instant (a write and the run it triggers, or the suite's fixed
  # clock) are two rows in a known order.
  def runs(limit),
    do: Repo.all(from(r in IndexRun, order_by: [desc: r.sequence], limit: ^limit))

  # ---- discussions ----

  def discussions(path),
    do: Repo.all(from(d in Discussion, where: d.path == ^path, order_by: d.opened_at))

  @doc "The resident's own kinds, oldest first (seshat#51)."
  @spec user_kinds() :: [UserKind.t()]
  def user_kinds, do: Repo.all(from(k in UserKind, order_by: [k.created_at, k.kind]))

  @doc "The system kinds' gates where they moved for the resident (seshat#51)."
  @spec kind_gates() :: [KindGate.t()]
  def kind_gates, do: Repo.all(from(g in KindGate, select: g))

  @doc "The gate proposals, newest first (seshat#51)."
  @spec kind_gate_proposals() :: [KindGateProposal.t()]
  def kind_gate_proposals,
    do: Repo.all(from(p in KindGateProposal, order_by: [desc: p.number]))
end
