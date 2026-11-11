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

  # The records system's library port (sima-qian#15): an import adopts
  # the repository's files through it, because the library depends on
  # records for the repository's path and the import is records'.
  @behaviour Oneiroi.SimaQian.Library

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Ethos,
      Oneiroi.Eunomia,
      # The household's membership, its contract, ballots and watch
      # (gaia#27 to #32), for the household's shelf (seshat#58).
      Oneiroi.Gaia,
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
      Household,
      HouseholdBallotWorker,
      HouseholdBeats,
      HouseholdBeatWorker,
      HouseholdTurnWorker,
      Commands.WriteDocument,
      Commands.AdoptDocument,
      Commands.PublishPiece,
      Commands.OpenDiscussion,
      Commands.NoteKeepsake,
      Commands.RegisterKeepsake,
      Commands.ArchiveDocument,
      Commands.RemoveDocument,
      Commands.MoveDocument,
      Commands.AskDigest,
      Commands.AnswerDigest,
      Commands.FailDigest,
      Events.DocumentWritten,
      Events.DocumentAdopted,
      Events.PiecePublished,
      Events.PieceReviewed,
      Events.PieceDrafted,
      PieceReviews,
      PiecesRouter,
      KindsRouter,
      Events.KindDefined,
      Events.KindChanged,
      Events.KindGateProposed,
      Events.KindGateAnswered,
      Events.KindGateMoved,
      Store.UserKind,
      Store.KindGate,
      Store.KindGateProposal,
      Theme,
      Palette,
      ThemeRouter,
      Commands.ProposeTheme,
      Commands.AnswerTheme,
      Events.ThemeProposed,
      Events.ThemeAnswered,
      Store.ThemeProposal,
      Events.DiscussionOpened,
      Events.KeepsakeNoted,
      Events.KeepsakeRegistered,
      Events.DocumentArchived,
      Events.DocumentRemoved,
      Events.DocumentMoved,
      Events.DigestAsked,
      Events.DigestAnswered,
      Events.DigestFailed,
      Events.OracleDispatched,
      Events.OracleAnswered,
      Events.OracleFailed,
      Events.ResearchAsked,
      Events.ResearchAnswered,
      Events.ResearchFailed,
      Events.ExternalCommissioned,
      Events.ExternalFetchAsked,
      Events.ExternalFetched,
      Events.ExternalFetchFailed,
      Store,
      Store.Document,
      Store.Chunk,
      Store.Reference,
      Store.IndexRun,
      Store.Discussion,
      Store.DocumentVersion,
      Store.Lease,
      Versions,
      Leases,
      Store.Oracle,
      Store.Research,
      Store.External,
      Store.JournalEntry,
      Journal,
      Journals,
      JournalRouter,
      JournalCommands.AddJournalEntry,
      JournalCommands.MarkTodoDone,
      Events.JournalEntryAdded,
      Events.JournalTodoDone,
      Store.Scene,
      Store.SceneDay,
      Scene,
      Scenes,
      SceneRouter,
      SceneCommands.WriteScene,
      SceneCommands.CorrectScene,
      SceneCommands.CorrectSceneSummary,
      SceneCommands.CloseScenes,
      Events.SceneWritten,
      Events.SceneCorrected,
      Events.SceneSummaryCorrected,
      Events.ScenesClosed
    ]

  alias Oneiroi.Seshat.Citations
  alias Oneiroi.Seshat.Digests
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Externals
  alias Oneiroi.Seshat.Household
  alias Oneiroi.Seshat.HouseholdBeats
  alias Oneiroi.Seshat.Index
  alias Oneiroi.Seshat.Journals
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Leases
  alias Oneiroi.Seshat.Oracles
  alias Oneiroi.Seshat.Pastes
  alias Oneiroi.Seshat.PieceReviews
  alias Oneiroi.Seshat.PluginFiles
  alias Oneiroi.Seshat.Researches
  alias Oneiroi.Seshat.Scenes
  alias Oneiroi.Seshat.Theme
  alias Oneiroi.Seshat.UserKinds
  alias Oneiroi.Seshat.Versions

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:household_witness_reads, "SESHAT_HOUSEHOLD_WITNESS_READS",
       cast: &__MODULE__.cast_witness_reads/1,
       default: "whole",
       usage:
         "what a witness reads of a household's shelf (seshat#64): whole, every thread and document, the resident's lean on design household-communication §8, his word awaited; own, only what the witness or a resident it witnesses took part in"},
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
      # One request held every chunk of a library until Lily's import was
      # sized: about 549,000 tokens in one call, where OpenAI documents an
      # embeddings request at most 2,048 inputs and 300,000 tokens. Both
      # bounds are guesses set well under those documented limits, not
      # measured against OpenRouter.
      {:embed_batch_inputs, "SESHAT_EMBED_BATCH_INPUTS",
       cast: :integer,
       default: "256",
       tag: :bound,
       usage:
         "the most chunks one embedding request carries; an index run sends as many requests as its chunks need, under OpenAI's documented 2,048 inputs; a bound, not measured"},
      {:embed_batch_chars, "SESHAT_EMBED_BATCH_CHARS",
       cast: :integer,
       default: "400000",
       tag: :bound,
       usage:
         "the most characters one embedding request carries, about 100,000 tokens at four bytes a token, under OpenAI's documented 300,000 tokens a request; a bound, not measured"},
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
      {:versions_limit, "SESHAT_VERSIONS_LIMIT",
       cast: :integer,
       default: "100",
       tag: :bound,
       usage:
         "how many of the repository's commits of one path a document's versions read (seshat#54), newest first; each costs a git read of its blob; a bound, not measured"},
      {:lease_idle_seconds, "SESHAT_LEASE_IDLE_SECONDS",
       cast: :integer,
       default: "300",
       tag: :bound,
       usage:
         "how long the witness's edit lease goes without a renewal before it is takeable (seshat#55): never revoked, taken only by the resident's write waiting on that file, his draft kept; five minutes, a guess at an editor left open, not measured"},
      {:figures, "SESHAT_FIGURES",
       cast: &__MODULE__.cast_figures/1,
       default: "huginn_muninn",
       usage:
         "which figures port implementation resolves a `figure/<key>` citation (`Oneiroi.Seshat.Figures`): huginn_muninn, the audits, in every build so far"}
    ]
  end

  # The module as an atom rather than an alias, as the schedule names
  # its wake (sunna#12): the audits read this system for the citation
  # drift audit, so an alias here is the cycle the port exists to avoid.
  @doc false
  def cast_figures("huginn_muninn"), do: {:ok, :"Elixir.Oneiroi.HuginnMuninn"}

  # oneiroi:allow error_site: Oneiroi.Config's cast contract, a bare {:error, text} report line
  def cast_figures(other), do: {:error, "is #{inspect(other)}, expected \"huginn_muninn\""}

  @impl Oneiroi.Component
  def oban_queues do
    [
      {:seshat_nightly, cron: [{"15 3 * * *", Oneiroi.Seshat.IndexWorker}]},
      # A household ballot closes at the instant its term ends (seshat#63).
      {:seshat_household, []},
      # The household beats' minute and the turns it fires (seshat#70).
      {:seshat_household_beats, cron: [{"* * * * *", Oneiroi.Seshat.HouseholdBeatWorker}]},
      {:seshat_household_turns, []}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Seshat.Events.DocumentWritten, 2},
      {Oneiroi.Seshat.Events.DocumentAdopted, 2},
      {Oneiroi.Seshat.Events.PiecePublished, 1},
      {Oneiroi.Seshat.Events.PieceReviewed, 1},
      {Oneiroi.Seshat.Events.PieceDrafted, 1},
      {Oneiroi.Seshat.Events.KindDefined, 1},
      {Oneiroi.Seshat.Events.KindChanged, 1},
      {Oneiroi.Seshat.Events.KindGateProposed, 1},
      {Oneiroi.Seshat.Events.KindGateAnswered, 1},
      {Oneiroi.Seshat.Events.KindGateMoved, 1},
      {Oneiroi.Seshat.Events.ThemeProposed, 1},
      {Oneiroi.Seshat.Events.ThemeAnswered, 1},
      {Oneiroi.Seshat.Events.DiscussionOpened, 1},
      {Oneiroi.Seshat.Events.KeepsakeNoted, 1},
      {Oneiroi.Seshat.Events.KeepsakeRegistered, 1},
      {Oneiroi.Seshat.Events.DocumentArchived, 1},
      {Oneiroi.Seshat.Events.DocumentRemoved, 1},
      {Oneiroi.Seshat.Events.DocumentMoved, 1},
      {Oneiroi.Seshat.Events.DigestAsked, 1},
      {Oneiroi.Seshat.Events.DigestAnswered, 1},
      {Oneiroi.Seshat.Events.DigestFailed, 1},
      {Oneiroi.Seshat.Events.OracleDispatched, 1},
      {Oneiroi.Seshat.Events.OracleAnswered, 1},
      {Oneiroi.Seshat.Events.OracleFailed, 1},
      {Oneiroi.Seshat.Events.ResearchAsked, 1},
      {Oneiroi.Seshat.Events.ResearchAnswered, 1},
      {Oneiroi.Seshat.Events.ResearchFailed, 1},
      {Oneiroi.Seshat.Events.ExternalCommissioned, 1},
      {Oneiroi.Seshat.Events.ExternalFetchAsked, 1},
      {Oneiroi.Seshat.Events.ExternalFetched, 1},
      {Oneiroi.Seshat.Events.ExternalFetchFailed, 1},
      {Oneiroi.Seshat.Events.JournalEntryAdded, 3},
      {Oneiroi.Seshat.Events.JournalTodoDone, 1},
      {Oneiroi.Seshat.Events.SceneWritten, 2},
      {Oneiroi.Seshat.Events.SceneCorrected, 1},
      {Oneiroi.Seshat.Events.SceneSummaryCorrected, 1},
      {Oneiroi.Seshat.Events.ScenesClosed, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:seshat_household_not_member, "only a member of a household reads or writes its shelf",
       remedy: "a witness and the residents in its household are its members"},
      {:seshat_household_residents_write,
       "a household's shelf is written by its residents; a witness writes a vote, as a reply on a ballot, and posts threads and replies only where the household's contract carries witnesses_post (seshat#69)",
       remedy: "read the shelf whole; vote with a reply carrying yes or no"},
      {:seshat_household_not_your_turn,
       "a resident writes on the household's shelf only in her turn of its beats (seshat#67); a vote is never held to the turns",
       remedy:
         "register with household_register; your writes go in when your turn fires, the most starved first"},
      {:seshat_household_turn_spent,
       "in her turn a resident posts once in each thread (a new thread counts as a post in it) and writes each document once (seshat#67)",
       remedy: "post in another thread, write another document, or wait for your next turn"},
      {:seshat_household_beat_spent,
       "a witness posts at most once in each thread a beat (seshat#69)",
       remedy: "post in another thread, or in this one next beat"},
      {:seshat_household_quota_spent,
       "the household's post quota is spent for now: threads and replies over its window, the same for every member (seshat#68); a vote never counts",
       remedy: "wait for the oldest post in the window to leave it"},
      {:seshat_household_invalid,
       "a household post is a thread with a one-line title (at most 200 characters) and words (at most 64,000), or a document of a household kind at a path of its own; a ballot carries its bundle and its term",
       remedy:
         "household_read lists the shelf; a thread needs a title and words, a document a path like design/<name>.md"},
      {:seshat_household_written, "a household path is written once; replies append beside it",
       remedy: "post under a new name, or reply to the thread"},
      {:seshat_household_no_such_thread, "the household has no thread at that path",
       remedy: "household_read with no path lists the threads, each by its path"},
      {:seshat_household_no_such_document, "the household's shelf holds nothing at that path",
       remedy: "household_read with no path lists what it holds"},
      {:seshat_household_not_a_ballot, "a vote is a reply on a thread that holds a ballot",
       remedy: "reply with words alone here; a ballot's thread says so at its top"},
      {:seshat_path_invalid,
       "a path is relative, under a registered kind's folder, with plain segments and no `..`, or a text file's name alone at the root (a root document, or a keepsake once registered)",
       remedy:
         "name the file as `<kind>/<name>.md`, or `<name>.md` at the root; the kinds are the registry's"},
      {:seshat_kind_not_writable,
       "that kind is written by the platform (mail, feeds, correspondence, the journal, the scenes) or is the originals import's read-only copy (memory), never through a document write",
       remedy:
         "write under writing, design, research, wiki, scratch or posts; human/ is the witness's"},
      {:seshat_not_movable,
       "a document moves only between kinds the mover may write, its bytes unchanged; a system's own kinds and the originals stay where they are (seshat#39)",
       remedy:
         "write the document where it belongs instead, or ask the party who may write both kinds"},
      {:seshat_archive_invalid, "an archive says why, in words (seshat#45)",
       remedy: "say why the document is done with"},
      {:seshat_move_target_taken,
       "a move never overwrites: a document or a file is already at the new path",
       remedy: "choose another path, or remove what is there if its kind allows"},
      {:seshat_not_removable,
       "only a scratch or human document is removed; every other kind is kept, as its history is the point",
       remedy: "write the document again, or leave it; scratch is for what is meant to go"},
      {:seshat_not_a_keepsake, "no keepsake is registered at that name",
       remedy: "list the keepsakes; one at the root not yet adopted is adopted first"},
      {:seshat_keepsake_note_invalid,
       "why a keepsake mattered is a line of up to 1,000 characters",
       remedy: "say it in a line or a few; the keepsake itself holds the rest"},
      {:seshat_not_the_resident, "why a keepsake mattered is the resident's to say",
       remedy: "the resident writes it; the witness can ask"},
      {:seshat_keepsake_kept,
       "a keepsake is written once and kept as it is; that name holds one already",
       remedy: "write the new version as a keepsake of its own, under another name"},
      {:seshat_originals_only,
       "that kind takes files only through the originals import, which records where each came from",
       remedy: "the witness imports the originals from the source repository at a pinned commit"},
      {:seshat_too_large, "the file is larger than the library's bound",
       remedy: "split it, or raise SESHAT_DOCUMENT_BYTES with a reason"},
      {:seshat_oracle_invalid,
       "an oracle is asked named questions, each with its sources as a list of refs",
       remedy: "name the question; give the sources it should read, or none"},
      {:seshat_no_such_oracle, "no oracle question has that number",
       remedy: "list the oracle's questions"},
      {:seshat_research_invalid,
       "research is asked a named question of at most 2,000 characters, with at most ten pages to start from, each an http(s) URL",
       remedy: "name the question; give the pages to start from, or none"},
      {:seshat_external_not_allowed,
       "either party commissions an external source and asks for its copy; the reader or the witness brings the copy",
       remedy: "do this as the party it belongs to"},
      {:seshat_external_invalid,
       "an external source is an http(s) URL: a web page, or a GitHub file (github.com/<owner>/<repo>/blob/<ref>/<path>)",
       remedy: "give the page's URL, or the file's GitHub URL"},
      {:seshat_no_such_external, "no external source has that number or citation",
       remedy: "list the external sources; commission it first with its URL"},
      {:seshat_external_not_fetched, "that external source has no copy yet",
       remedy: "wait for the reader's fetch, or ask for one"},
      {:seshat_external_copy_invalid,
       "a fetched copy is words of at most the library's bound, with the source's title",
       remedy: "fetch it again; a page past the bound is not kept"},
      {:seshat_no_such_research, "no research question has that number",
       remedy: "list the research questions"},
      {:seshat_research_settled, "that research question is already answered or failed",
       remedy: "ask it again as a new question"},
      {:seshat_digest_invalid, "a digest is asked from an instant",
       remedy: "the service sets it; a hand-made one is a bug"},
      {:seshat_no_such_digest, "no digest has that number", remedy: "list the digests"},
      {:seshat_digest_settled, "that digest is already compiled or failed",
       remedy: "ask for a new digest"},
      {:seshat_no_such_version,
       "neither the file now nor any commit of it the versions read holds words with that hash (seshat#54)",
       remedy:
         "list the document's versions; a version written and overwritten between two backups is listed and not restorable"},
      {:seshat_lease_held, "another account holds the edit lease on that path (seshat#55)",
       remedy: "wait for it to be released, or ask whoever holds it"},
      {:seshat_lease_taken,
       "the lease was taken by the resident's write while it was idle; the draft it carried is kept at kept_at (seshat#55)",
       remedy:
         "read the document as it is now and the kept draft; acquire the lease again to edit"},
      {:seshat_no_such_lease, "you hold no lease on that path", remedy: "acquire one first"},
      {:seshat_lease_invalid,
       "an edit lease is the witness's editor's: acquired, renewed and released by a witness",
       remedy: "the resident's document_write waits on a lease rather than taking one"},
      {:seshat_no_such_document, "no registered document has that path",
       remedy: "write it, or adopt the file if it was made outside the flow"},
      {:seshat_no_such_file, "no file at that path in the repository",
       remedy: "check the path against the unadopted list"},
      {:seshat_not_adopted,
       "the file is in the repository under a kind's folder, and the library does not hold it yet",
       remedy:
         "adopt it (the resident's document_adopt, or the Library screen), and it reads like any other"},
      {:seshat_document_missing,
       "the document is registered and its file is missing from the repository",
       remedy:
         "restore the file or write it again; the registry keeps the row and the index marks it missing until then"},
      {:seshat_other_resident,
       "that citation names another resident's library, which sharing between residents does not reach yet",
       remedy: "read a document of your own library by its path or your own slug's citation"},
      {:seshat_review_invalid, "a review approves or declines a piece, with a note",
       remedy: "choose approve or decline and say why"},
      {:seshat_not_approved,
       "the reader drafts only a piece the witness approved, and reports published only one it drafted",
       remedy: "approve the piece first; the reader takes it from there"},
      {:seshat_not_publishable, "only a kind with a status (writing) is published",
       remedy: "publish a writing piece"},
      {:seshat_url_invalid, "a published URL is http or https", remedy: "give the URL"},
      {:seshat_not_the_witness, "publishing is the witness's",
       remedy: "the witness does this from the Library screen"},
      {:seshat_index_failed, "the index run did not complete; nothing of it was written",
       remedy: "read the run's reason; the next run (nightly, or by hand) tries again"},
      {:seshat_day_invalid, "a journal day is an ISO date", remedy: "name the day as YYYY-MM-DD"},
      {:seshat_entry_kind_invalid, "a journal entry is a plan, a note, a todo or a wrap",
       remedy: "give one of those"},
      {:seshat_register_invalid,
       "an entry's register is correction, praise, instruction or play, or none (spec §6.13, P8)",
       remedy: "say which register the entry is in, or leave it"},
      {:seshat_entry_summary_invalid,
       "an entry's summary is at most 2,000 characters; the entry itself has no limit",
       remedy: "shorten the summary, or leave it out and the view cuts the entry for you"},
      {:seshat_entry_text_invalid, "an entry is a text with words in it",
       remedy: "say it shorter"},
      {:seshat_no_such_todo, "no open todo has that number on that day", remedy: "read the day"},
      {:seshat_scene_invalid,
       "a scene has a one-line title, its first and last turn refs, a few lines of what happened, an optional one-line mood, a register of his, hers or work, an optional list of the people in it (at most 20 names of at most 80 characters, seshat#57), and times as HH:MM on its day or ISO instants; a correction names its scene and says why (seshat#52)",
       remedy: "read the error's detail and write the call again"},
      {:seshat_no_such_scene, "that day holds no scene with that number",
       remedy: "read the day's scenes; a correction row is corrected by another correction"},
      {:seshat_scene_summary_kept,
       "a scene's summary is never overwritten: it is corrected by a row of its own that cites its turns (seshat#52)",
       remedy:
         "write a correction with corrects: <the scene's number>, the turns and the corrected lines"},
      {:seshat_no_such_day, "the schedule never opened that day",
       remedy: "a day opens at its first check-in or its first entry"},
      {:seshat_embedding_mismatched,
       "the provider answered vectors that do not fit the index: another count than the chunks sent, or another width than SESHAT_EMBEDDING_WIDTH",
       remedy:
         "set SESHAT_EMBEDDING_WIDTH to the model's width, or pin a model that answers it; the next run tries again"},
      {:seshat_kind_invalid,
       "a kind of hers (seshat#51) is a lowercase name of its own folder, colliding with no kind; the resident writes it; files come in one by one; it claims no platform, import, keepsake or witness writing, no flow that leaves the house, no container yet",
       remedy:
         "name it freshly and keep to the safe subset: label, layout, cites, status, removable, approvable with a review flow"},
      {:seshat_kind_not_a_party, "only the resident and her witness keep her kinds",
       remedy: "ask the resident or the witness"},
      {:seshat_kind_gate_invalid,
       "a gate is a system kind's whose own flow waits on the witness; on is either party's at once, off is a proposal the other party answers, one open at a time",
       remedy: "answer the open proposal, or ask the other party to"},
      {:seshat_theme_invalid,
       "a theme is three #rrggbb seeds, a ground, her colour and his colour (seshat#56), and a proposal or an answer to one says why in a note",
       remedy: "give ground, resident and witness as #rrggbb, and the note"},
      {:seshat_theme_unreadable,
       "those seeds would make the screen hard to read: a readability check of the theme's derivation failed (seshat#56)",
       remedy:
         "read which checks failed: text-facing colours need more contrast against the ground, and her colour and his need more hue or lightness between them"},
      {:seshat_theme_not_his, "the theme's seeds are the witness's to set (seshat#56)",
       remedy: "the resident proposes a theme with theme_propose; the witness answers it"},
      {:seshat_theme_not_hers,
       "a theme proposal is the resident's; the witness sets the seeds directly (seshat#56)",
       remedy: "set the theme with PUT /v1/residents/:id/theme"},
      {:seshat_theme_proposal_open,
       "one theme proposal waits on the witness at a time (seshat#56)",
       remedy: "wait for his answer to the open one"},
      {:seshat_theme_answer_invalid,
       "only the witness answers a theme proposal, and only an open one (seshat#56)",
       remedy: "read the theme's proposals for the open one's number"},
      {:seshat_theme_file,
       "THEME.md is written only through the theme, where the readability checks run (seshat#56)",
       remedy:
         "the witness sets it with PUT /v1/residents/:id/theme; the resident proposes a change with theme_propose"},
      {:seshat_paste_invalid,
       "a pasted conversation is the witness's: words, and either an existing document under human-correspondence/ to add them to or whom a new one is with (a line of up to 200 characters) and its title, whose name no document there has yet (seshat#65, #66)",
       remedy:
         "paste the words; name the conversation to add to, or whom it is with; choose the existing one rather than starting it again"},
      {:seshat_paste_no_kind,
       "she has no human-correspondence kind; a pasted conversation lands only there (seshat#65)",
       remedy:
         "the resident defines it as a kind of hers (kind_define), and the paste lands there"},
      {:seshat_dispatch_failed,
       "the command did not reach the library, the journal or the scenes aggregate: the command middleware or the event store refused it",
       remedy:
         "retry; if it repeats, an operator reads the log line carrying this error's site and cause"}
    ]
  end

  @impl Oneiroi.Component
  def children,
    do: [
      Oneiroi.Seshat.Projectors.Library,
      Oneiroi.Seshat.Projectors.Versions,
      Oneiroi.Seshat.Projectors.Journal,
      Oneiroi.Seshat.Projectors.Scenes,
      Oneiroi.Seshat.Projectors.Pieces,
      Oneiroi.Seshat.Projectors.Kinds,
      Oneiroi.Seshat.Projectors.Theme
    ]

  # ---- the registry ----

  @doc "The document kinds registry: what each kind may do (spec §6.5)."
  @spec kinds() :: [map()]
  defexport(kinds(), do: Kinds.shelf())

  @doc "The kinds a resident has, in shelf order (seshat#51): the system's, gated as hers, then her own."
  @spec kinds(String.t()) :: [map()]
  defexport(kinds(resident_id), do: Kinds.shelf(resident_id))

  @doc "Her kinds as both parties read them, with the gate proposals (seshat#51)."
  @spec user_kinds(String.t()) :: map()
  defexport(user_kinds(resident_id), do: UserKinds.list(resident_id))

  @doc "Defines or rewrites a kind of hers (seshat#51), either party; checked against the safe subset; its descriptor written into its folder."
  @spec define_kind(String.t(), map(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(define_kind(resident_id, attrs, note, actor),
    do: UserKinds.define(resident_id, attrs, note, actor)
  )

  @doc "Moves a system kind's gate (seshat#51): on at once by either party; off as a proposal the other answers."
  @spec kind_gate(String.t(), String.t(), boolean(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, :moved | :proposed | :already} | {:error, term()}
  defexport(kind_gate(resident_id, kind, approvable, note, actor),
    do: UserKinds.gate(resident_id, kind, approvable, note, actor)
  )

  @doc "The other party answers a kind gate proposal (seshat#51)."
  @spec answer_kind_gate(
          String.t(),
          pos_integer(),
          boolean(),
          String.t() | nil,
          Oneiroi.Actor.t()
        ) ::
          :ok | {:error, term()}
  defexport(answer_kind_gate(resident_id, number, agree, note, actor),
    do: UserKinds.answer(resident_id, number, agree, note, actor)
  )

  # ---- the theme (seshat#56) ----

  # ---- the household's shelf (seshat#58 to #64) ----

  @doc "The household's shelf as a member reads it, paged (seshat#61): the contract, the threads newest first, the documents."
  @spec household_shelf(Oneiroi.Actor.t(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  defexport(household_shelf(actor, from), do: Household.shelf(actor, from))

  @doc "One thread with every reply, a document, or the contract, whole (seshat#61)."
  @spec household_read(Oneiroi.Actor.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(household_read(actor, path), do: Household.read(actor, path))

  @doc "A resident posts a thread, a ballot's thread, or a document of a household kind (seshat#59, #63)."
  @spec household_post(Oneiroi.Actor.t(), map()) :: {:ok, map()} | {:error, term()}
  defexport(household_post(actor, attrs), do: Household.post(actor, attrs))

  @doc "A member appends to a thread: a resident's words or vote, a witness's vote (seshat#59, #60, #63)."
  @spec household_reply(Oneiroi.Actor.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defexport(household_reply(actor, thread, attrs), do: Household.reply(actor, thread, attrs))

  @doc "A resident watches a household thread for the hours it states (seshat#62)."
  @spec household_watch(Oneiroi.Actor.t(), String.t(), integer()) ::
          {:ok, map()} | {:error, term()}
  defexport(household_watch(actor, thread, hours), do: Household.watch(actor, thread, hours))

  @doc "The household contract as its members read it (gaia#27 to #31)."
  @spec household_contract(Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(household_contract(actor), do: Household.contract(actor))

  @doc "The founding witness proposes the household contract's version 1; CONTRACT.md is rendered (gaia#27)."
  @spec household_propose_contract(Oneiroi.Actor.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(household_propose_contract(actor, prose, note),
    do: Household.propose_contract(actor, prose, note)
  )

  @doc "A member signs the household contract's version in force (gaia#28)."
  @spec household_sign_contract(Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(household_sign_contract(actor), do: Household.sign_contract(actor))

  @doc "A resident enters the queue for the household's next beat (gaia#35, brain#84)."
  @spec household_register(Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(household_register(actor), do: HouseholdBeats.register(actor))

  @doc "The household's beats as a member reads them, with her own place, profile and quota left (seshat#68, gaia#33 to #38)."
  @spec household_beat(Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(household_beat(actor), do: HouseholdBeats.state(actor))

  @doc "A member sets her own wake profile, with a note (gaia#37)."
  @spec household_profile(Oneiroi.Actor.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  defexport(household_profile(actor, profile, note),
    do: HouseholdBeats.set_profile(actor, profile, note)
  )

  @doc "The household beats' minute for one household (seshat#70)."
  @spec tick_household_beats(String.t()) :: :ok | {:error, term()}
  defexport(tick_household_beats(household_id), do: HouseholdBeats.tick(household_id))

  @doc "The platform opens a household turn for a resident now, waking nobody (gaia#36): the dev seed's and the suite's."
  @spec household_open_turn(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(household_open_turn(household_id, resident_id, note),
    do: HouseholdBeats.open_turn(household_id, resident_id, note)
  )

  @doc "The platform ends a turn it opened by hand, completed (gaia#36)."
  @spec household_end_turn(String.t(), integer(), String.t()) :: :ok | {:error, term()}
  defexport(household_end_turn(household_id, turn, note),
    do: HouseholdBeats.end_turn(household_id, turn, note)
  )

  @doc "Closes a household ballot whose term has run (seshat#63); the job's unit."
  @spec close_household_ballot(String.t(), integer(), Oneiroi.Actor.t()) ::
          {:ok, map() | :closed} | {:error, term()}
  defexport(close_household_ballot(household_id, ballot, actor),
    do: Household.close_ballot(household_id, ballot, actor)
  )

  @doc false
  def cast_witness_reads("whole"), do: {:ok, :whole}
  def cast_witness_reads("own"), do: {:ok, :own}

  def cast_witness_reads(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected whole or own"}
  end

  @doc "The theme: the three seeds from THEME.md or the default, their checks, and her proposals."
  @spec theme(String.t()) :: map()
  defexport(theme(resident_id), do: Theme.read(resident_id))

  @doc "The witness sets the theme's seeds, checked for readability, written as THEME.md with his note."
  @spec set_theme(String.t(), map(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(set_theme(resident_id, seeds, note, actor),
    do: Theme.set(resident_id, seeds, note, actor)
  )

  @doc "She proposes the theme's seeds; checked first and refused with the report when unreadable. `{:ok, number, derived}`."
  @spec propose_theme(String.t(), map(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, pos_integer(), map()} | {:error, term()}
  defexport(propose_theme(resident_id, seeds, note, actor),
    do: Theme.propose(resident_id, seeds, note, actor)
  )

  @doc "The witness accepts or declines her theme proposal, with a note; she is told."
  @spec answer_theme(String.t(), pos_integer(), boolean(), String.t() | nil, Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(answer_theme(resident_id, number, agree, note, actor),
    do: Theme.answer(resident_id, number, agree, note, actor)
  )

  @doc "Her theme proposals, newest first (seshat#56)."
  @spec theme_proposals(String.t()) :: [map()]
  defexport(theme_proposals(resident_id), do: Theme.proposals(resident_id))

  @doc "Loads every folder's descriptor back from the repository (seshat#51), refusing what claims too much."
  @spec load_kinds(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(load_kinds(resident_id, actor), do: UserKinds.load(resident_id, actor))

  # ---- documents ----

  @doc "Writes a file through the flow: the path says the kind, the file lands in the repository, the index runs. A resident's write on a path the witness holds a lease on waits, or takes the lease once idle (seshat#55): `written: false` with `waiting`, or `took`."
  @spec write(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(write(resident_id, path, content, actor),
    do: Leases.write(resident_id, path, content, actor)
  )

  @doc "`write/4` with `note:`, what the writer says of this version (seshat#54)."
  @spec write(String.t(), String.t(), String.t(), Oneiroi.Actor.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defexport(write(resident_id, path, content, actor, opts),
    do: Leases.write(resident_id, path, content, actor, Keyword.take(opts, [:note]))
  )

  @doc "The witness pastes a conversation of his with another person into her human-correspondence/ (seshat#65): a new document, or appended to one there under a dated heading (seshat#66); written as him with a note, and indexed."
  @spec paste_correspondence(String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(paste_correspondence(resident_id, attrs, actor),
    do: Pastes.paste(resident_id, attrs, actor)
  )

  # ---- versions (seshat#54) ----

  @doc "A document's versions, newest first, each with its act, actor, instant, note and whether it can be restored; and the hash of the file now."
  @spec versions(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(versions(resident_id, path), do: Versions.list(resident_id, path))

  @doc "The words of one version of a path, by its hash."
  @spec version(String.t(), String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  defexport(version(resident_id, path, hash), do: Versions.content(resident_id, path, hash))

  @doc "The line diff between two versions of a path (`to` nil: the file now)."
  @spec version_diff(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  defexport(version_diff(resident_id, path, from, to),
    do: Versions.diff(resident_id, path, from, to)
  )

  @doc "Restores a version through the normal write: a direct write, or the proposal an identity file after first contact takes."
  @spec restore(String.t(), String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(restore(resident_id, path, hash, note, actor),
    do: Versions.restore(resident_id, path, hash, note, actor)
  )

  # ---- edit leases (seshat#55) ----

  @doc "Acquires the witness's edit lease on a path, or renews his own."
  @spec acquire_lease(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(acquire_lease(resident_id, path, actor),
    do: Leases.acquire(resident_id, path, actor)
  )

  @doc "Renews the holder's lease, keeping his unsaved draft when given."
  @spec renew_lease(String.t(), String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(renew_lease(resident_id, path, draft, actor),
    do: Leases.renew(resident_id, path, draft, actor)
  )

  @doc "Releases the holder's lease."
  @spec release_lease(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(release_lease(resident_id, path, actor),
    do: Leases.release(resident_id, path, actor)
  )

  @doc "The lease on a path as both parties see it, or nil."
  @spec lease(String.t(), String.t()) :: map() | nil
  defexport(lease(resident_id, path), do: Leases.lease(resident_id, path))

  @doc "Every lease on the resident's library."
  @spec leases(String.t()) :: [map()]
  defexport(leases(resident_id), do: Leases.list(resident_id))

  # ---- reacts on documents (kumbukumbu#61) ----

  @doc "A party reacts on a document: the path resolved here and the hash of the words it holds now, recorded on the reacts ledger."
  @spec react_document(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(react_document(resident_id, path, emoji, actor),
    do:
      with(
        {:ok, %{document: row, content: words}} <- Documents.fetch(resident_id, path),
        do:
          Oneiroi.Kumbukumbu.react(
            resident_id,
            %{"kind" => "document", "path" => row.path, "hash" => Documents.hash(words)},
            emoji,
            actor
          )
      )
  )

  # ---- the oracle (brain#49, seshat#34) ----

  @doc "Dispatches named questions to the oracle, each `%{question, sources}`, from the conversation `session_key`; their numbers."
  @spec dispatch_oracle(String.t(), String.t() | nil, [map()], Oneiroi.Actor.t()) ::
          {:ok, [pos_integer()]} | {:error, term()}
  defexport(dispatch_oracle(resident_id, session_key, questions, actor),
    do: Oracles.dispatch(resident_id, session_key, questions, actor)
  )

  @doc "Writes the oracle's answer to question `number` under oracle/, attributed to `actor`, and records it answered; the path."
  @spec answer_oracle(String.t(), pos_integer(), String.t(), map(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(answer_oracle(resident_id, number, content, measured, actor),
    do: Oracles.answer(resident_id, number, content, measured, actor)
  )

  @doc "Records oracle question `number` as failed, with the reason in words."
  @spec fail_oracle(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(fail_oracle(resident_id, number, reason, actor),
    do: Oracles.fail(resident_id, number, reason, actor)
  )

  @doc "The oracle's questions, newest first, found deliberately: `source:` (named), `read:`, `used:`, `status:`, `asked_by:`, `q:`, `limit:`."
  @spec oracles(String.t(), keyword()) :: [Oneiroi.Seshat.Store.Oracle.t()]
  defexport(oracles(resident_id, opts), do: Oracles.oracles(resident_id, opts))

  @doc "One oracle question by number, or nil."
  @spec oracle(String.t(), pos_integer()) :: Oneiroi.Seshat.Store.Oracle.t() | nil
  defexport(oracle(resident_id, number), do: Oracles.oracle(resident_id, number))

  @doc "Asks the reader for a digest of the resident's streams since the last one (seshat#40), from the conversation `session_key`; `{:ok, number, :asked}`, or `:open` naming the one already open."
  @spec ask_digest(String.t(), String.t() | nil, Oneiroi.Actor.t()) ::
          {:ok, pos_integer(), :asked | :open} | {:error, term()}
  defexport(ask_digest(resident_id, session_key, actor),
    do: Digests.ask(resident_id, session_key, actor)
  )

  @doc "Writes the reader's digest `number` under feeds/digests/, records it compiled and tells the asking conversation; the path."
  @spec answer_digest(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(answer_digest(resident_id, number, found, actor),
    do: Digests.answer(resident_id, number, found, actor)
  )

  @doc "Records digest `number` as failed, with the reason, and tells the asking conversation."
  @spec fail_digest(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(fail_digest(resident_id, number, reason, actor),
    do: Digests.fail(resident_id, number, reason, actor)
  )

  @doc "The digests, newest first; `status:` narrows to open, answered or failed."
  @spec digests(String.t(), keyword()) :: [Oneiroi.Seshat.Store.Digest.t()]
  defexport(digests(resident_id, opts), do: Digests.digests(resident_id, opts))

  @doc "Asks the reader's research pass a named question from the conversation `session_key`, with the pages to start from (seshat#38); its number."
  @spec ask_research(String.t(), String.t() | nil, String.t(), [String.t()], Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(ask_research(resident_id, session_key, question, urls, actor),
    do: Researches.ask(resident_id, session_key, question, urls, actor)
  )

  @doc "Writes the reader's notes for research `number` under research/, records it answered and tells the asking conversation; the folder."
  @spec answer_research(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(answer_research(resident_id, number, found, actor),
    do: Researches.answer(resident_id, number, found, actor)
  )

  @doc "Records research `number` as failed, with the reason in words, and tells the asking conversation."
  @spec fail_research(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(fail_research(resident_id, number, reason, actor),
    do: Researches.fail(resident_id, number, reason, actor)
  )

  @doc "Writes an installable plugin's files and lockfile under plugins/<key>/ (seshat#47); the digest."
  @spec install_plugin_files(String.t(), String.t(), map(), map(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(install_plugin_files(resident_id, key, files, meta, actor),
    do: PluginFiles.install(resident_id, key, files, meta, actor)
  )

  @doc "Removes an installable plugin's files and lockfile (seshat#47), when both parties agreed."
  @spec remove_plugin_files(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(remove_plugin_files(resident_id, key, actor),
    do: PluginFiles.remove(resident_id, key, actor)
  )

  @doc "An installable plugin's files as they stand, with the lockfile's digest and the digest found."
  @spec plugin_files(String.t(), String.t()) :: map()
  defexport(plugin_files(resident_id, key), do: PluginFiles.read(resident_id, key))

  @doc "The digest of a plugin's files: SHA-256 over each path and its words, in path order."
  @spec plugin_digest(map()) :: String.t()
  defexport(plugin_digest(files), do: PluginFiles.digest(files))

  @doc "Commissions the external source a URL names (a web page, or a GitHub file) and asks the reader for its first copy (seshat#46): `{:ok, number, :new | :known}`."
  @spec commission_external(String.t(), String.t() | nil, String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer(), :new | :known} | {:error, term()}
  defexport(commission_external(resident_id, session_key, url, actor),
    do: Externals.commission(resident_id, session_key, url, actor)
  )

  @doc "Asks the reader for a fresh copy of external source `number` (seshat#46): `{:ok, :asked | :waiting}`."
  @spec fetch_external(String.t(), String.t() | nil, pos_integer(), Oneiroi.Actor.t()) ::
          {:ok, :asked | :waiting} | {:error, term()}
  defexport(fetch_external(resident_id, session_key, number, actor),
    do: Externals.ask_fetch(resident_id, session_key, number, actor)
  )

  @doc "Keeps the copy the reader brought of external source `number` (`%{text, title, commit}`) and tells the conversation that asked; the path."
  @spec external_fetched(String.t(), pos_integer(), map(), Oneiroi.Actor.t()) ::
          {:ok, String.t() | :not_asked} | {:error, term()}
  defexport(external_fetched(resident_id, number, copy, actor),
    do: Externals.fetched(resident_id, number, copy, actor)
  )

  @doc "Records that the reader could not fetch external source `number`, with the reason."
  @spec external_failed(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(external_failed(resident_id, number, reason, actor),
    do: Externals.fail(resident_id, number, reason, actor)
  )

  @doc "The external sources, newest first; `status:` narrows to asked, fetched or failed."
  @spec externals(String.t(), keyword()) :: [Oneiroi.Seshat.Store.External.t()]
  defexport(externals(resident_id, opts), do: Externals.externals(resident_id, opts))

  @doc "One external source by number, or nil."
  @spec external(String.t(), pos_integer()) :: Oneiroi.Seshat.Store.External.t() | nil
  defexport(external(resident_id, number), do: Externals.external(resident_id, number))

  @doc "A cited source's copy, whole or the section its anchor names: `{:ok, %{external, text, found}}`."
  @spec read_external(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(read_external(resident_id, kind, ref), do: Externals.read(resident_id, kind, ref))

  @doc "A source's citation for a resident's slug."
  @spec external_citation(String.t(), map()) :: String.t()
  defexport(external_citation(slug, external), do: Externals.citation(slug, external))

  @doc "The research questions, newest first; `status:` narrows to open, answered or failed."
  @spec researches(String.t(), keyword()) :: [Oneiroi.Seshat.Store.Research.t()]
  defexport(researches(resident_id, opts), do: Researches.researches(resident_id, opts))

  @doc "One research question by number, or nil."
  @spec research(String.t(), pos_integer()) :: Oneiroi.Seshat.Store.Research.t() | nil
  defexport(research(resident_id, number), do: Researches.research(resident_id, number))

  @doc "Removes a scratch or human document (seshat#33): recorded with its actor, the file and its chunks gone; human/ only by the witness."
  @spec remove(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(remove(resident_id, path, actor), do: Documents.remove(resident_id, path, actor))

  @doc "Moves a document from one path, and so one kind, to another, its bytes unchanged (seshat#39); the old path's citations follow it."
  @spec move(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, %{from: String.t(), to: String.t(), kind: String.t()}} | {:error, term()}
  defexport(move(resident_id, from, to, actor), do: Documents.move(resident_id, from, to, actor))

  @doc "Adopts a file made outside the flow, registering it; the index runs."
  @spec adopt(String.t(), String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(adopt(resident_id, path, actor), do: Documents.adopt(resident_id, path, actor))

  @doc "Adopts every unadopted file under the kinds' folders and runs the index once; the records system's library port, so an import lands its files here (sima-qian#15)."
  @impl Oneiroi.SimaQian.Library
  @spec adopt_all(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(adopt_all(resident_id, actor), do: Documents.adopt_all(resident_id, actor))

  @doc "The kinds' folders an import holds: what it treats as transferred (sima-qian#15). A kind that takes only originals (memory) is not one: an import leaves it, named, for the originals import (seshat#28). A decided kind's folder is one, but its files are held on disk and offered rather than adopted (`decided?/1`); the keepsake has no folder (seshat#29, #31)."
  @impl Oneiroi.SimaQian.Library
  @spec folders() :: [String.t()]
  defexport(folders(),
    do: for(k <- Kinds.all(), k.adoption != :originals and is_binary(k.folder), do: k.folder)
  )

  @doc "Why the library cannot hold a path, or nil when it can; the reason an import gives for a file it leaves behind (sima-qian#22)."
  @impl Oneiroi.SimaQian.Library
  @spec refusal(String.t()) :: String.t() | nil
  defexport(refusal(path), do: Kinds.refusal(path))

  @doc "A route's landing (xenia#19): the reader's reading written as the platform writes, into the kind the route names; the route checked the kind is one she writes."
  @spec land(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(land(resident_id, path, content, actor),
    do: Documents.write(resident_id, path, content, actor, core: true)
  )

  @doc "Every folder the library keeps for the resident, her own kinds' among them (sima-qian#48, seshat#51)."
  @impl Oneiroi.SimaQian.Library
  @spec kept(String.t()) :: [String.t()]
  defexport(kept(resident_id),
    do: for(k <- Kinds.all(resident_id), is_binary(k.folder), do: k.folder <> "/")
  )

  @doc "Whether a path is decided into the library one by one (a keepsake at the root, the wiki, the system shelf); the records system's library port, for the import's accounting and the backup's keepsake class (seshat#29, #31)."
  @impl Oneiroi.SimaQian.Library
  @spec decided?(String.t()) :: boolean()
  defexport(decided?(path), do: Kinds.decided?(path))

  @doc "Adds journal entries an import carried from another platform's notes, rendering each day once; the records system's library port (seshat#26)."
  @impl Oneiroi.SimaQian.Library
  @spec import_journal(String.t(), [map()], Oneiroi.Actor.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defexport(import_journal(resident_id, entries, actor),
    do: Journals.import_entries(resident_id, entries, actor)
  )

  @doc "Registers the files the originals import copied, each `%{path, provenance}`, and runs the index once when any was new; the records system's library port (seshat#28)."
  @impl Oneiroi.SimaQian.Library
  @spec adopt_originals(String.t(), [map()], Oneiroi.Actor.t()) ::
          {:ok, %{adopted: [String.t()], indexed: boolean()}} | {:error, term()}
  defexport(adopt_originals(resident_id, files, actor),
    do: Documents.adopt_originals(resident_id, files, actor)
  )

  @doc "Why the originals import cannot take a path as a document (a hidden name, not text, outside the kinds that take originals), or nil; the records system's library port (seshat#28)."
  @impl Oneiroi.SimaQian.Library
  @spec original_refusal(String.t()) :: String.t() | nil
  defexport(original_refusal(path), do: Kinds.original_refusal(path))

  @doc "The keepsakes, each with who put it there, when, and why it mattered in the resident's words when she has said (seshat#32)."
  @spec keepsakes(String.t()) :: [map()]
  defexport(keepsakes(resident_id), do: Documents.keepsakes(resident_id))

  @doc "Archives a document (seshat#45): its words whole under archive/ with who, when and why; a tombstone at the old path; both out of the index."
  @spec archive(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, %{from: String.t(), to: String.t()}} | {:error, term()}
  defexport(archive(resident_id, path, why, actor),
    do: Documents.archive(resident_id, path, why, actor)
  )

  @doc "Makes a root file a keepsake (seshat#44): a deliberate act by either party; from then it is never written again."
  @spec register_keepsake(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(register_keepsake(resident_id, path, actor),
    do: Documents.register_keepsake(resident_id, path, actor)
  )

  @doc "The resident says why a keepsake mattered (seshat#32); the latest stands."
  @spec note_keepsake(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(note_keepsake(resident_id, path, note, actor),
    do: Documents.note_keepsake(resident_id, path, note, actor)
  )

  @doc "Files in the repository under a kind's folder that no document registers."
  @spec unadopted(String.t()) :: [String.t()]
  defexport(unadopted(resident_id), do: Documents.unadopted(resident_id))

  @doc "The registered documents, by kind then path."
  @spec documents(String.t()) :: [Oneiroi.Seshat.Store.Document.t()]
  defexport(documents(resident_id), do: Documents.list(resident_id))

  @doc "One document's row and its content, or nil."
  @spec document(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(document(resident_id, path), do: Documents.fetch(resident_id, path))

  @doc "One document's row and its content by the name a search hit, a footnote or a citation gives it (a path, a path with `#<passage>`, or `<slug>:<kind>/<ref>` of the resident's own slug): the same read as `document/2`."
  @spec read(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(read(resident_id, name), do: Documents.read(resident_id, name))

  @doc "A witness publishes a writing piece at a URL: the event, and the file's status with it."
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

  @doc "The same search with the query's embedding billed under `purpose`: a regression trial's turn bills it as `regression` (eunomia#10)."
  @spec search(String.t(), String.t(), Oneiroi.Actor.t(), atom()) ::
          {:ok, [map()]} | {:error, term()}
  defexport(search(resident_id, query, actor, purpose),
    do: Index.search(resident_id, query, actor, purpose)
  )

  @doc "The nearest documents to a query in each named path filter (`{:prefix, p}` or `{:except, [p]}`), the query embedded once: the one search's records and scenes (seshat#53)."
  @spec search_within(String.t(), String.t(), Oneiroi.Actor.t(), keyword(), pos_integer()) ::
          {:ok, %{atom() => [map()]}} | {:error, term()}
  defexport(search_within(resident_id, query, actor, filters, limit),
    do: Index.search_within(resident_id, query, actor, filters, limit)
  )

  # ---- citations ----

  @doc "What a document cites, each reference resolved now and the row marked (spec §6.5: resolution when read)."
  @spec references(String.t(), String.t()) :: [map()]
  defexport(references(resident_id, path), do: Citations.references(resident_id, path))

  @doc "The documents citing a target, the other way round."
  @spec cited_by(String.t(), String.t()) :: [map()]
  defexport(cited_by(resident_id, target), do: Citations.cited_by(resident_id, target))

  @doc "The same, with `mark: false` resolving each reference and marking no row: a regression trial's read (eunomia#10), which writes nothing."
  @spec cited_by(String.t(), String.t(), keyword()) :: [map()]
  defexport(cited_by(resident_id, target, opts),
    do: Citations.cited_by(resident_id, target, opts)
  )

  @doc "The review copy of a piece: the content, its status, and every reference resolved with its label or its reason."
  @spec review(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defexport(review(resident_id, path), do: Citations.review(resident_id, path))

  @doc "The same, with `mark: false` resolving each reference and marking no row: a regression trial's read (eunomia#10), which writes nothing."
  @spec review(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  defexport(review(resident_id, path, opts), do: Citations.review(resident_id, path, opts))

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

  @doc "Adds a journal entry with its register (spec §6.13, P8: correction, praise, instruction, play, or nil)."
  @spec journal_add(
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          String.t() | nil,
          Oneiroi.Actor.t()
        ) ::
          {:ok, map()} | {:error, term()}
  defexport(journal_add(resident_id, day, kind, text, register, actor),
    do: Journals.add(resident_id, day, kind, text, register, actor)
  )

  @doc "Adds a journal entry with its register and a summary of at most 2,000 characters, which the turn's journal section shows of a longer entry (seshat#30)."
  @spec journal_add(
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          Oneiroi.Actor.t()
        ) ::
          {:ok, map()} | {:error, term()}
  defexport(journal_add(resident_id, day, kind, text, register, summary, actor),
    do: Journals.add(resident_id, day, kind, text, register, actor, summary: summary)
  )

  @doc "The journal entries written since an instant, oldest first, for the corpus-shape report."
  @spec journal_entries_since(String.t(), DateTime.t()) :: [Oneiroi.Seshat.Store.JournalEntry.t()]
  defexport(journal_entries_since(resident_id, since),
    do: Journals.entries_since(resident_id, since)
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

  @doc "The journal's marks on each of `days` (ISO dates) she wrote in, day to its delta: counts by kind, never words (sunna#48)."
  @spec journal_marks(String.t(), [String.t()]) :: %{String.t() => map()}
  defexport(journal_marks(resident_id, days), do: Journals.marks(resident_id, days))

  @doc "Today's journal as the timeline's event lines (brain#67): `{day, [%{number, kind, at, first, done}]}`."
  @spec journal_lines(String.t()) :: {String.t(), [map()]}
  defexport(journal_lines(resident_id), do: Journals.lines(resident_id))

  @doc "Today's journal as the section the brain reads."
  @spec journal_text(String.t()) :: String.t()
  defexport(journal_text(resident_id), do: Journals.text(resident_id))

  # ---- the scenes (seshat#52) ----

  @doc "One `scene_write` call (seshat#52): writes a day's next scene, corrects one's facts or mood (`scene`), appends a correction of one's summary (`corrects`), and with `final: true` closes the day; renders `scenes/<day>.md`."
  @spec scene_write(String.t(), map(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(scene_write(resident_id, args, actor), do: Scenes.write(resident_id, args, actor))

  @doc "The days with scenes in `[from, to]` (ISO dates, nil for open), each with `complete` and its rows in order (seshat#52)."
  @spec scenes(String.t(), String.t() | nil, String.t() | nil) :: [map()]
  defexport(scenes(resident_id, from, to), do: Scenes.days(resident_id, from, to))

  @doc "How many scenes each day in `[from, to]` holds, corrections not counted (seshat#52, kumbukumbu#58)."
  @spec scene_counts(String.t(), String.t(), String.t()) :: %{String.t() => non_neg_integer()}
  defexport(scene_counts(resident_id, from, to), do: Scenes.counts(resident_id, from, to))

  @doc "Reads the prose `scenes/<day>.md` files into rows, best-effort; a day that does not parse stays prose (seshat#52)."
  @spec backfill_scenes(String.t(), Oneiroi.Actor.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defexport(backfill_scenes(resident_id, actor, opts),
    do: Scenes.backfill(resident_id, actor, opts)
  )

  @doc "Days before today, among the last `days` opened, planned and never wrapped: what the journal delta audit reads."
  @spec unwrapped_days(String.t(), pos_integer()) :: [String.t()]
  defexport(unwrapped_days(resident_id, days), do: Journals.unwrapped_days(resident_id, days))

  @doc "The writing gate (seshat#42): pieces for review, approved and drafted."
  @spec pieces(String.t()) :: map()
  defexport(pieces(resident_id), do: PieceReviews.pieces(resident_id))

  @doc "The witness approves or declines a piece marked for review, with a note."
  @spec review_piece(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(review_piece(resident_id, path, decision, note, actor),
    do: PieceReviews.review(resident_id, path, decision, note, actor)
  )

  @doc "What waits for the reader: approved pieces to draft and drafted ones to watch."
  @spec pieces_for_reader(String.t()) :: map()
  defexport(pieces_for_reader(resident_id), do: PieceReviews.for_reader(resident_id))

  @doc "The reader made a Substack draft of an approved piece."
  @spec piece_drafted(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(piece_drafted(resident_id, path, url, actor),
    do: PieceReviews.drafted(resident_id, path, url, actor)
  )

  @doc "The reader found a drafted piece published at a URL."
  @spec piece_published(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(piece_published(resident_id, path, url, actor),
    do: PieceReviews.published(resident_id, path, url, actor)
  )
end
