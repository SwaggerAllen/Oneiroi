defmodule Oneiroi.Seshat do
  @moduledoc """
  The library (spec §6.5): document kinds, the vector index over every
  folder of the resident's repository, citations both ways, writing's
  review and publish, and the adoption of files made outside the flow.
  Path is kind and the registry says what a kind may do; only
  resident-authored kinds mint citation edges; a reference is resolved
  when it is read, never when it is indexed; a file is re-embedded only
  when its hash or the model changes.

  The files are the resident's repository on disk (sima-qian), where the
  backup commits them; the rows here are derived from them and from the
  library's own stream, `library-<resident_id>`.
  """
  use Oneiroi.System, slug: :seshat

  # The records system's library port (sima-qian #15): an import adopts
  # the repository's files through it, because the library depends on
  # records for the repository's path and the import is records'.
  @behaviour Oneiroi.SimaQian.Library

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Eunomia,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Oneiroi.SimaQian,
      Oneiroi.Sunna,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason,
      Oban,
      Pgvector
    ],
    exports: [
      Error,
      Kinds,
      Library,
      Documents,
      Citations,
      Index,
      Figures,
      Router,
      IndexWorker,
      Commands.WriteDocument,
      Commands.AdoptDocument,
      Commands.PublishPiece,
      Commands.OpenDiscussion,
      Events.DocumentWritten,
      Events.DocumentAdopted,
      Events.PiecePublished,
      Events.DiscussionOpened,
      Store,
      Store.Document,
      Store.Chunk,
      Store.Reference,
      Store.IndexRun,
      Store.Discussion,
      Store.JournalEntry,
      Journal,
      Journals,
      JournalRouter,
      JournalCommands.AddJournalEntry,
      JournalCommands.MarkTodoDone,
      Events.JournalEntryAdded,
      Events.JournalTodoDone
    ]

  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Index
  alias Oneiroi.Seshat.Journals
  alias Oneiroi.Seshat.Kinds

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:embedding_model, "SESHAT_EMBEDDING_MODEL",
       default: "openai/text-embedding-3-small",
       usage:
         "the embedding model, pinned platform-wide (spec §6.5): a change re-embeds every file on its next index run; the default is the model the spec's width was taken from, not measured here"},
      {:embedding_width, "SESHAT_EMBEDDING_WIDTH",
       cast: :integer,
       default: "1536",
       tag: :bound,
       usage:
         "the width of the index's vectors, spec §6.5's 1,536; the column is declared at this width, so a model answering another width fails the run rather than the table"},
      {:chunk_chars, "SESHAT_CHUNK_CHARS",
       cast: :integer,
       default: "2000",
       tag: :bound,
       usage:
         "how many characters a chunk of a file holds before the next one starts, split on paragraphs; a guess at what a search wants back, not measured"},
      {:document_bytes, "SESHAT_DOCUMENT_BYTES",
       cast: :integer,
       default: "262144",
       tag: :bound,
       usage:
         "the most a file written through the flow may hold, spec §6.6's 256 KiB per note carried here; a bound"},
      {:search_limit, "SESHAT_SEARCH_LIMIT",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage: "how many chunks a search returns at most; a bound"},
      {:figures, "SESHAT_FIGURES",
       cast: &__MODULE__.cast_figures/1,
       default: "huginn_muninn",
       usage:
         "which figures port implementation resolves a `figure/<key>` citation (`Oneiroi.Seshat.Figures`): huginn_muninn, the audits, in every build so far"}
    ]
  end

  # The module as an atom rather than an alias, as the schedule names
  # its wake (sunna #12): the audits read this system for the citation
  # drift audit, so an alias here is the cycle the port exists to avoid.
  @doc false
  def cast_figures("huginn_muninn"), do: {:ok, :"Elixir.Oneiroi.HuginnMuninn"}
  def cast_figures(other), do: {:error, "is #{inspect(other)}, expected \"huginn_muninn\""}

  @impl Oneiroi.Component
  def oban_queues do
    [{:seshat_nightly, cron: [{"15 3 * * *", Oneiroi.Seshat.IndexWorker}]}]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Seshat.Events.DocumentWritten, 1},
      {Oneiroi.Seshat.Events.DocumentAdopted, 1},
      {Oneiroi.Seshat.Events.PiecePublished, 1},
      {Oneiroi.Seshat.Events.DiscussionOpened, 1},
      {Oneiroi.Seshat.Events.JournalEntryAdded, 1},
      {Oneiroi.Seshat.Events.JournalTodoDone, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:seshat_path_invalid,
       "a path is relative, under a registered kind's folder, with plain segments and no `..`",
       remedy: "name the file as `<kind>/<name>.md`; the kinds are the registry's"},
      {:seshat_kind_not_writable,
       "that kind is written by the platform (mail, feeds, correspondence, the journal), never through a document write",
       remedy: "write under writing, design, research, wiki or posts"},
      {:seshat_too_large, "the file is larger than the library's bound",
       remedy: "split it, or raise SESHAT_DOCUMENT_BYTES with a reason"},
      {:seshat_no_such_document, "no registered document has that path",
       remedy: "write it, or adopt the file if it was made outside the flow"},
      {:seshat_no_such_file, "no file at that path in the repository",
       remedy: "check the path against the unadopted list"},
      {:seshat_not_publishable, "only a kind with a status (writing) is published",
       remedy: "publish a writing piece"},
      {:seshat_url_invalid, "a published URL is http or https", remedy: "give the URL"},
      {:seshat_not_the_steward, "publishing is the steward's",
       remedy: "the steward does this from the Library screen"},
      {:seshat_index_failed, "the index run did not complete; nothing of it was written",
       remedy: "read the run's reason; the next run (nightly, or by hand) tries again"},
      {:seshat_day_invalid, "a journal day is an ISO date", remedy: "name the day as YYYY-MM-DD"},
      {:seshat_entry_kind_invalid, "a journal entry is a plan, a note, a todo or a wrap",
       remedy: "give one of those"},
      {:seshat_entry_text_invalid, "an entry is one text of at most 2,000 characters",
       remedy: "say it shorter"},
      {:seshat_no_such_todo, "no open todo has that number on that day", remedy: "read the day"},
      {:seshat_no_such_day, "the schedule never opened that day",
       remedy: "a day opens at its first check-in or its first entry"}
    ]
  end

  @impl Oneiroi.Component
  def children, do: [Oneiroi.Seshat.Projectors.Library, Oneiroi.Seshat.Projectors.Journal]

  # ---- the registry ----

  @doc "The document kinds registry: what each kind may do (spec §6.5)."
  @spec kinds() :: [map()]
  defexport(kinds(), do: Kinds.all())

  # ---- documents ----

  @doc "Writes a file through the flow: the path says the kind, the file lands in the repository, the index runs."
  @spec write(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(write(resident_id, path, content, actor),
    do: Documents.write(resident_id, path, content, actor)
  )

  @doc "Adopts a file made outside the flow, registering it; the index runs."
  @spec adopt(String.t(), String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(adopt(resident_id, path, actor), do: Documents.adopt(resident_id, path, actor))

  @doc "Adopts every unadopted file under the kinds' folders and runs the index once; the records system's library port, so an import lands its files here (sima-qian #15)."
  @impl Oneiroi.SimaQian.Library
  @spec adopt_all(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(adopt_all(resident_id, actor), do: Documents.adopt_all(resident_id, actor))

  @doc "The kinds' folders: what an import treats as transferred (sima-qian #15)."
  @impl Oneiroi.SimaQian.Library
  @spec folders() :: [String.t()]
  defexport(folders(), do: Enum.map(Kinds.all(), & &1.folder))

  @doc "Files in the repository under a kind's folder that no document registers."
  @spec unadopted(String.t()) :: [String.t()]
  defexport(unadopted(resident_id), do: Documents.unadopted(resident_id))

  @doc "The registered documents, by kind then path."
  @spec documents(String.t()) :: [Oneiroi.Seshat.Store.Document.t()]
  defexport(documents(resident_id), do: Documents.list(resident_id))

  @doc "One document's row and its content, or nil."
  @spec document(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(document(resident_id, path), do: Documents.fetch(resident_id, path))

  @doc "A steward publishes a writing piece at a URL: the event, and the file's status with it."
  @spec publish(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(publish(resident_id, path, url, actor),
    do: Documents.publish(resident_id, path, url, actor)
  )

  @doc "Links a session to a piece as its discussion."
  @spec discuss(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(discuss(resident_id, path, session_key, actor),
    do: Documents.discuss(resident_id, path, session_key, actor)
  )

  @doc "The sessions linked to a piece."
  @spec discussions(String.t(), String.t()) :: [Oneiroi.Seshat.Store.Discussion.t()]
  defexport(discussions(resident_id, path), do: Documents.discussions(resident_id, path))

  # ---- the index ----

  @doc "Runs the index: every registered file, re-embedded only when its hash or the model changed; three statements and no model call when nothing did."
  @spec index(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(index(resident_id, actor), do: Index.run(resident_id, actor))

  @doc "The latest index runs."
  @spec index_runs(String.t(), pos_integer()) :: [Oneiroi.Seshat.Store.IndexRun.t()]
  defexport(index_runs(resident_id, limit), do: Index.runs(resident_id, limit))

  @doc "Searches the index: the nearest chunks to the query, with their documents; an empty library calls no model."
  @spec search(String.t(), String.t(), Oneiroi.Actor.t()) :: {:ok, [map()]} | {:error, term()}
  defexport(search(resident_id, query, actor), do: Index.search(resident_id, query, actor))

  # ---- citations ----

  @doc "What a document cites, each reference resolved now and the row marked (spec §6.5: resolution when read)."
  @spec references(String.t(), String.t()) :: [map()]
  defexport(references(resident_id, path), do: Citations.references(resident_id, path))

  @doc "The documents citing a target, the other way round."
  @spec cited_by(String.t(), String.t()) :: [map()]
  defexport(cited_by(resident_id, target), do: Citations.cited_by(resident_id, target))

  @doc "The review copy of a piece: the content, its status, and every reference resolved with its label or its reason."
  @spec review(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(review(resident_id, path), do: Citations.review(resident_id, path))

  @doc "The copy for publishing: the frontmatter and every citation stripped."
  @spec publish_copy(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defexport(publish_copy(resident_id, path), do: Citations.publish_copy(resident_id, path))

  @doc "References that resolved once and do not now: what the citation drift audit reads (spec §6.13)."
  @spec drift(String.t()) :: [map()]
  defexport(drift(resident_id), do: Citations.drift(resident_id))

  # ---- the journal (spec §6.5, F29) ----

  @doc "Adds a journal entry (plan, note, todo, wrap) to a day, today in the resident's zone when nil; returns its number."
  @spec journal_add(String.t(), String.t() | nil, String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(journal_add(resident_id, day, kind, text, actor),
    do: Journals.add(resident_id, day, kind, text, actor)
  )

  @doc "Marks a todo done."
  @spec journal_done(String.t(), String.t(), pos_integer(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(journal_done(resident_id, day, number, actor),
    do: Journals.done(resident_id, day, number, actor)
  )

  @doc "A day with its entries and delta, or nil when the schedule never opened it."
  @spec journal_day(String.t(), String.t()) :: map() | nil
  defexport(journal_day(resident_id, day), do: Journals.day(resident_id, day))

  @doc "The latest days with their deltas, newest first."
  @spec journal_days(String.t(), pos_integer()) :: [map()]
  defexport(journal_days(resident_id, limit), do: Journals.days(resident_id, limit))

  @doc "Today's journal as the section the brain reads."
  @spec journal_text(String.t()) :: String.t()
  defexport(journal_text(resident_id), do: Journals.text(resident_id))

  @doc "Days before today, among the last `days` opened, planned and never wrapped: what the journal delta audit reads."
  @spec unwrapped_days(String.t(), pos_integer()) :: [String.t()]
  defexport(unwrapped_days(resident_id, days), do: Journals.unwrapped_days(resident_id, days))
end
