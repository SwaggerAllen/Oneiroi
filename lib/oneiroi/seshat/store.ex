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
      field(:done_at, :utc_datetime_usec)
    end

    @type t :: %__MODULE__{}
  end

  # ---- the journal ----

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
end
