defmodule Oneiroi.Brain do
  @moduledoc """
  The resident's canonical agent loop (spec §5): one process per active
  session, a turn as assemble, call, stream, capture. Named for its
  function until the author names it (`design/names.md`), as the client
  is.

  A turn goes through the ledger's port and nothing else, is captured at
  its end as an ordinary `TurnCaptured` whether the model answered or
  refused, and records what it drew on. A budget stop is told honestly:
  the notice lands in the transcript as a system message both parties
  read in the same place (spec §5, §6.11).
  """
  use Oneiroi.System, slug: :brain
  @behaviour Oneiroi.Sunna.Wake
  @behaviour Oneiroi.Eunomia.Trial

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Req,
      Req.Response,
      Commanded.Event.Handler,
      Oneiroi.AgathosDaimon,
      Oneiroi.Ethos,
      Oneiroi.Eunomia,
      Oneiroi.Gaia,
      Oneiroi.Glitnir,
      Oneiroi.HuginnMuninn,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Oneiroi.Seshat,
      Oneiroi.SimaQian,
      Oneiroi.Sunna,
      Oneiroi.Xenia,
      Jason,
      # The oracle's worker (brain#49), as every system with a worker has.
      Oban
    ],
    exports: [Error, Session, Turn, Tools, Compaction, Drafting, FixtureRun, DevSeed]

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Adapter
  alias Oneiroi.Brain.BackfillNotes
  alias Oneiroi.Brain.Checkin
  alias Oneiroi.Brain.Creation
  alias Oneiroi.Brain.Drafting
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.FreeTime
  alias Oneiroi.Brain.HouseQueue
  alias Oneiroi.Brain.LabelPropagation
  alias Oneiroi.Brain.NeedsYou
  alias Oneiroi.Brain.NightPasses
  alias Oneiroi.Brain.PluginConsent
  alias Oneiroi.Brain.Preview
  alias Oneiroi.Brain.QueueDocs
  alias Oneiroi.Brain.Reactions
  alias Oneiroi.Brain.Retry
  alias Oneiroi.Brain.Session
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Turn
  alias Oneiroi.Brain.WaitingOnHer
  alias Oneiroi.Kumbukumbu

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def feature_flags, do: [:brain_pulls_off]

  # The platform's pull requests, read for the resident (brain#71): its
  # own code under review, so nothing of hers crosses.
  @impl Oneiroi.Component
  def externals do
    [
      {:github_pulls,
       adapter: Oneiroi.Brain.Pulls.GitHub,
       fake: Oneiroi.Brain.Pulls.Fake,
       kill_switch: :brain_pulls_off,
       classification: :operational}
    ]
  end

  @impl Oneiroi.Component
  def config do
    [
      {:chat_model, "BRAIN_CHAT_MODEL",
       default: "openai/gpt-4o-mini",
       usage:
         "the chat model until the witness's pin arrives with regression (spec §6.4): a placeholder chosen for being cheap and widely served, not measured"},
      {:draft_model, "BRAIN_DRAFT_MODEL",
       default: "z-ai/glm-5.3",
       usage:
         "the model that drafts in the creation flow: the prompt path, Write it with me and suggested trials (agathos-daimon#42); big enough to write a person, cheap enough to start one"},
      {:transcript_messages, "BRAIN_TRANSCRIPT_MESSAGES",
       cast: :integer,
       default: "40",
       tag: :bound,
       usage:
         "how many of the session's messages since its compaction a turn is shown as its live transcript; a bound"},
      {:compact_after_messages, "BRAIN_COMPACT_AFTER_MESSAGES",
       cast: :integer,
       default: "80",
       tag: :bound,
       usage:
         "how many messages a session gathers since its last compaction before a turn opens by compacting it (spec §5); twice the live window, a guess until a model's context is measured against real sessions"},
      {:batch_messages, "BRAIN_BATCH_MESSAGES",
       cast: :integer,
       default: "4",
       tag: :bound,
       usage:
         "how many of the witness's messages that queued while a turn ran the next turn takes together (brain#66), each with a turn's tool rounds; the rest wait for the turn after, so a batch never has fewer rounds a message than separate turns, and a guess"},
      {:timeline_lines, "BRAIN_TIMELINE_LINES",
       cast: :integer,
       default: "12",
       tag: :bound,
       usage:
         "how many lines each layer of the timeline shows (brain#67): today's journal rows, the last 30 days' weighed moments, and her life so far past her pins, which always show; the newest kept, a guess"},
      {:plugin_catalog, "BRAIN_PLUGIN_CATALOG",
       default: "",
       usage:
         "the folder of the installable plugins' catalog (brain#68), each a folder with plugin.json and files/; empty, the release's priv/plugins"},
      {:oracle_tool_rounds, "BRAIN_ORACLE_TOOL_ROUNDS",
       cast: :integer,
       default: "24",
       tag: :bound,
       usage:
         "how many rounds of tool calls the oracle may make before it is asked for its answer from what it has read (brain#50); three times a turn's, since the oracle exists for the long reads, and a guess"},
      {:tool_rounds, "BRAIN_TOOL_ROUNDS",
       cast: :integer,
       default: "8",
       tag: :bound,
       usage:
         "how many rounds of tool calls one turn may make before the model's last words stand as the reply, or, when it wrote none, it is asked once more with no tool callable (brain#50); a bound against a model that loops"},
      {:tool_rounds_max, "BRAIN_TOOL_ROUNDS_MAX",
       cast: :integer,
       default: "24",
       tag: :bound,
       usage:
         "the most tool rounds a turn may extend itself to with rounds_extend (brain#99), once a turn; the oracle's own number, and the anti-loop wall a looping turn meets after its one extension; a guess"},
      {:context_tokens, "BRAIN_CONTEXT_TOKENS",
       cast: :integer,
       default: "128000",
       tag: :bound,
       usage:
         "the model window the capacity alarm (spec §5, P9) measures the always-loaded prefix against, in tokens estimated at four bytes each; a bound, the smallest window among the models the platform expects, not measured per model"},
      {:capacity_alarm_percent, "BRAIN_CAPACITY_ALARM_PERCENT",
       cast: :integer,
       default: "90",
       tag: :bound,
       usage:
         "the share of the window at which the prefix is flagged on the turn (spec §5, P9): a bound from the proposal, not measured"},
      {:library_read_chars, "BRAIN_LIBRARY_READ_CHARS",
       cast: :integer,
       default: "12000",
       tag: :bound,
       usage:
         "how many characters of a document one library_read answers before it says where the next page starts (brain#43): about 3,000 tokens at four bytes a token, a guess at what one read may take of a turn's context, not measured"},
      {:tool_result_chars, "BRAIN_TOOL_RESULT_CHARS",
       cast: :integer,
       default: "16000",
       tag: :bound,
       usage:
         "the most characters any one tool call answers into a turn, the rest cut with a note saying how much: about 4,000 tokens, room for a library page; a bound, not measured. Unbounded, one search answered 2.4M characters and a turn asked a model for 1.9M tokens (2026-11-03)"},
      {:history_tool_chars, "BRAIN_HISTORY_TOOL_CHARS",
       cast: :integer,
       default: "2000",
       tag: :bound,
       usage:
         "how many characters of a past tool answer a replayed transcript carries: the call and the head of its answer, enough to know what was looked at; the model can call again for the rest. A bound, not measured"},
      {:compaction, "BRAIN_COMPACTION",
       cast: &__MODULE__.cast_on_off/1,
       default: "off",
       usage:
         "whether a conversation that outgrows its window is compacted into a summary (on) or truncated (off, brain#60): off, the turn reads the last BRAIN_TRANSCRIPT_MESSAGES messages whole with a line saying how many came before and that transcript_read pages back through them, and no summary is written or shown. Off since 2026-11-06, the witness's call: compaction's summaries were part of the month's corruption"},
      {:history_stamps, "BRAIN_HISTORY_STAMPS",
       cast: &__MODULE__.cast_on_off/1,
       default: "off",
       usage:
         "whether each message of the transcript the resident is shown carries when it was said, inline at its head (brain#58, #59): on or off. Off since 2026-11-06: within an hour of it going on, her model began opening replies with mangled stamps and two turns degenerated into hundreds of lines, stamp fragments through them; on again only by a deliberate choice"},
      {:oracle_batch, "BRAIN_ORACLE_BATCH",
       cast: :integer,
       default: "5",
       tag: :bound,
       usage:
         "how many questions one oracle dispatch may carry (brain#49), each its own parallel read; a guess at a batch worth its spend"},
      {:oracle_chunk_chars, "BRAIN_ORACLE_CHUNK_CHARS",
       cast: :integer,
       default: "40000",
       tag: :bound,
       usage:
         "how many characters of the named sources the oracle reads at once (about 10,000 tokens); past it, the sources are read in parts of this size first and their notes given to the answer; a guess"},
      {:oracle_max_chunks, "BRAIN_ORACLE_MAX_CHUNKS",
       cast: :integer,
       default: "60",
       tag: :bound,
       usage:
         "how many parts of one source the oracle reads for one question, each a call carrying her prefix; past it the rest are named as unread; a bound on one question's spend, a guess"},
      {:source_dir, "BRAIN_SOURCE_DIR",
       default: ".",
       usage:
         "where the platform's own source is, for the resident to read the code running her (brain#46): the image copies it to /app/source and sets this; a checkout's root otherwise"},
      {:pulls_client, "BRAIN_PULLS_CLIENT",
       cast: &__MODULE__.cast_pulls_client/1,
       default: "github",
       usage:
         "which pull requests port answers the resident's pr_meta and pr_diffs (brain#71): github in every real build, fake in test (conventions §9)"},
      {:pulls_repo, "BRAIN_PULLS_REPO",
       default: "SwaggerAllen/Oneiroi",
       usage:
         "the repository whose pull requests the resident reads (brain#71), as owner/name: the platform's own"},
      {:github_token, "BRAIN_GITHUB_TOKEN",
       secret: true,
       required: false,
       usage:
         "a GitHub token for reading pull requests (brain#71), for a higher rate limit than anonymous reads; read-only scope is enough, and the platform's public repository needs none"},
      {:pulls_diff_chars, "BRAIN_PULLS_DIFF_CHARS",
       cast: :integer,
       default: "20000",
       tag: :bound,
       usage:
         "how much of one file's diff one pr_diffs read returns before saying how to read on (brain#71); a bound on one read's share of a turn, a guess"},
      {:turn_timeout_ms, "BRAIN_TURN_TIMEOUT_MS",
       cast: :integer,
       default: "300000",
       tag: :bound,
       usage:
         "how long a caller waits on a session process for a turn before giving up; a bound above the port's own timeout. Five minutes (the witness, 2026-11-08): a work turn that wrote a whole design doc ran 3 min 22 s and the old 3 minutes orphaned its run"}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:brain_queue_document_absent,
       "a document named to the house queue is one that exists: no file is at that citation (sunna#95)",
       remedy:
         "name the file by the citation its reader gives it; a house document is house/<the house>:doc/<path>"},
      {:brain_turn_failed,
       "the turn did not complete: the witness's words were kept and no reply was captured (brain#45)",
       remedy:
         "the provider failure is recorded as a capture failure on the session; send the message again"},
      {:brain_no_such_plugin, "no plugin in the catalog has that key",
       remedy: "plugin_list names every plugin and its key"},
      {:brain_no_such_failure, "no unsettled failed turn has that ref (brain#89)",
       remedy: "read the capture failures; one already run again or dismissed is settled"},
      {:brain_nothing_running, "no turn is running in that conversation to stop",
       remedy: "nothing to do: the turn had already ended"},
      {:brain_tool_raised, "a tool failed inside the platform; the turn went on without it",
       remedy: "nothing for her to do; the log line carries the cause for the platform's team"},
      {:brain_resident_guarded,
       "the resident is still forming, or woken and not yet in their first agreement: nothing but the witness reaches them (and, while forming, only his regression trials)",
       remedy:
         "wake them when the trials and the model are settled; agree your first contract, and the rest of the house opens"},
      {:brain_wake_outlasted,
       "the wake's turn ran past the wait (BRAIN_TURN_TIMEOUT_MS) and is still running in its session",
       remedy:
         "nothing to do: the turn finishes and is captured as any other; what waited on it went on"},
      {:brain_turn_crashed, "the turn's process stopped before it answered",
       remedy: "send the message again; the session's next message still runs"},
      {:brain_budget_stopped,
       "the budget line is spent: the message and a notice saying so were captured, and no reply was asked for",
       remedy:
         "raise the budget line, or wait for its period to turn; the details carry the captured turn and the ledger's stop"},
      {:brain_no_such_resident, "no resident has that id",
       remedy: "read the id off the resident list"},
      {:brain_file_unknown, "the file is not one of the resident's identity files",
       remedy: "draft one of the identity files the resident system names"},
      {:brain_creation_closed, "the resident has woken, so the gifts are no longer drafted whole",
       remedy:
         "after first contact a change is a proposal: draft one file with Write it with me and propose it"},
      {:brain_read_unreadable, "the read came back in a form the notes could not be read from",
       remedy: "ask for the read again; the call was billed under drafting"},
      {:brain_trials_unreadable,
       "the suggested trials came back in a form the trials could not be read from",
       remedy: "ask again; the call was billed under drafting"},
      {:brain_oracle_silent, "the oracle's reading answered no words",
       remedy: "ask the question again; it may need narrower sources"},
      {:brain_summary_empty, "the model answered the compaction with no words",
       remedy: "nothing was compacted; the next turn tries again"},
      {:brain_path_invalid,
       "a path in the source or the repository is relative and plain: no .., no absolute path, no .git or build output",
       remedy: "name the file from the root, as the listing shows it"},
      {:brain_path_absent, "nothing is at that path", remedy: "list the folder first"},
      {:brain_pulls_invalid,
       "a pull request is named by its number, and pr_diffs by the files it changes, as pr_meta lists them (brain#71)",
       remedy: "give the number, and for diffs a list of file paths from pr_meta"},
      {:brain_pulls_absent, "the platform's repository has no pull request with that number",
       remedy: "check the number"},
      {:brain_pulls_failed, "GitHub did not answer the pull request read (brain#71)",
       remedy: "try again in a while; a rate limit passes within the hour"},
      {:brain_path_sealed,
       "the file is sealed: the judge's prompts are witness-only, by an explicit list (brain#46)",
       remedy: "ask the witness; the list itself is in the spec and open to argument"},
      {:brain_path_binary, "the file is not text", remedy: "read a text file"},
      {:brain_session_unavailable, "the session's process could not be started",
       remedy: "retry the message; the log line carries the cause"}
    ]
  end

  @impl Oneiroi.Component
  def processes,
    do: [
      {:brain_registry, :local},
      {:brain_sessions, :local},
      {:brain_turns, :local},
      {:brain_needs_you_watchers, :local},
      {:brain_needs_you_live, :local}
    ]

  # The oracle's reads (brain#49): on demand, no cron. The needs-you
  # push (brain#77): each minute, as the schedule's tick is.
  @impl Oneiroi.Component
  def oban_queues,
    do: [
      {:brain_oracle, []},
      # A forward out of a sealed mail wake (kumbukumbu#98).
      {:brain_forward, []},
      {:brain_needs_you, cron: [{"* * * * *", Oneiroi.Brain.NeedsYouPushWorker}]}
    ]

  @impl Oneiroi.Component
  def pubsub_topics, do: [:session, :needs_you]

  # A turn, timed by the span collector (apsu#26).
  @impl Oneiroi.Component
  def telemetry_events, do: [[:oneiroi, :brain, :turn]]

  @impl Oneiroi.Component
  def children do
    [
      {Registry, keys: :unique, name: :brain_registry},
      {DynamicSupervisor, name: :brain_sessions, strategy: :one_for_one},
      # The turns a session runs off its own process (brain#45).
      {Task.Supervisor, name: :brain_turns},
      # The bell pushed (brain#94): who watches it, and the process that
      # computes it once a burst of notices for them.
      {Registry, keys: :duplicate, name: :brain_needs_you_watchers},
      Oneiroi.Brain.NeedsYou.Live,
      # The button to Lily (gaia#20): each platform report a letter.
      Oneiroi.Brain.Triage
    ]
  end

  @doc "Runs a failed turn again (brain#89): settled as retried, then started on the turn supervisor; `{:ok, what it does}`."
  @spec retry_failure(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(retry_failure(resident_id, turn_ref, actor),
    do: Retry.one(resident_id, turn_ref, actor)
  )

  @doc "Runs every turn the provider refused for credit again, each purpose once (brain#89)."
  @spec retry_credit_failures(String.t(), Oneiroi.Actor.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  defexport(retry_credit_failures(resident_id, actor),
    do: Retry.credits(resident_id, actor)
  )

  @doc "Free time remembered (brain#53): the latest runs, newest first, with the conversation each ran in, its turns, and the receipts of what it made."
  @spec free_time_history(String.t(), pos_integer()) :: [map()]
  defexport(free_time_history(resident_id, limit),
    do: FreeTime.history(resident_id, limit, Tools.writes())
  )

  @doc "Rounds remembered (sunna#39): the latest, newest first, with the conversation each ran in, its turns, and the receipts of what left it."
  @spec round_history(String.t(), pos_integer()) :: [map()]
  defexport(round_history(resident_id, limit),
    do: FreeTime.rounds(resident_id, limit, Tools.writes())
  )

  @doc """
  Takes the witness's message under the client's ref and answers at once
  (brain#45): `running`, `queued` with how many wait ahead, or
  `duplicate` when that ref was taken before. The turn's outcome arrives
  on the session topic. `domain:` (a slug, or nil for the common
  room) names the domain its turn is in (kumbukumbu#72).
  """
  @spec submit(String.t(), String.t(), String.t(), Oneiroi.Actor.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defexport(submit(resident_id, session_key, text, actor, ref, opts \\ []),
    do:
      with(
        :ok <- admitted(resident_id, session_key, actor),
        do: Session.submit(resident_id, session_key, text, actor, ref, opts)
      )
  )

  @doc "The plugin catalog with the resident's state and every proposal (brain#68)."
  @spec plugins(String.t()) :: map()
  defexport(plugins(resident_id), do: PluginConsent.list(resident_id))

  @doc "Proposes a change to a plugin: install, remove, on or off, with its why (brain#68)."
  @spec propose_plugin(String.t(), String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, pos_integer()} | {:error, term()}
  defexport(propose_plugin(resident_id, key, change, note, actor),
    do: PluginConsent.propose(resident_id, key, change, note, actor)
  )

  @doc "Answers a plugin proposal, agreed or declined, with a note (brain#68)."
  @spec answer_plugin(String.t(), pos_integer(), boolean(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(answer_plugin(resident_id, number, agree, note, actor),
    do: PluginConsent.answer(resident_id, number, agree, note, actor)
  )

  @doc "Switches an installable plugin off at once, either party's alone (brain#68, position #68)."
  @spec switch_plugin_off(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(switch_plugin_off(resident_id, key, note, actor),
    do: PluginConsent.switch_off(resident_id, key, note, actor)
  )

  @doc "Everything waiting on the witness's decision across the systems, oldest first (brain#65); it only shows."
  @spec needs_you(String.t()) :: [map()]
  defexport(needs_you(resident_id), do: NeedsYou.list(resident_id))

  @doc "Takes a house queue activity (sunna#80), its artifact's head read now for the pin guard."
  @spec queue_take(String.t(), pos_integer(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_take(household_id, task, act, actor),
    do: HouseQueue.take(household_id, task, act, actor)
  )

  @doc "Finishes a house queue activity, its artifact's head read now; `pin` defaults to it."
  @spec queue_finish(String.t(), pos_integer(), String.t(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_finish(household_id, task, act, attrs, actor),
    do: HouseQueue.finish(household_id, task, act, attrs, actor)
  )

  @doc "Decides a house queue review on what the reviewer read, the head read now beside it."
  @spec queue_decide(String.t(), pos_integer(), String.t(), map(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(queue_decide(household_id, task, act, attrs, actor),
    do: HouseQueue.decide(household_id, task, act, attrs, actor)
  )

  @doc "Registers the calling process as watching the resident's bell (brain#94): its list is computed once a burst of notices and broadcast on the `needs_you` topic as `{resident_id, entries}`."
  @spec watch_needs_you(String.t()) :: :ok
  defexport(watch_needs_you(resident_id), do: NeedsYou.Live.watch(resident_id))

  @doc "Everything waiting on the resident, oldest first (brain#76): the witness's proposals she has not answered, his unread letters, the files his lease holds her from; it only shows."
  @spec waiting_on_her(String.t()) :: [map()]
  defexport(waiting_on_her(resident_id), do: WaitingOnHer.list(resident_id))

  @doc "Stops the turn running in a session (brain#61): `by` is `:witness` (his Stop); `{:error, _}` when nothing runs."
  @spec stop(String.t(), String.t(), atom()) :: :ok | {:error, term()}
  defexport(stop(resident_id, session_key, by), do: Session.stop(resident_id, session_key, by))

  @doc "What a session is generating now (brain#114): the running turn's ref and those queued behind it."
  @spec working(String.t(), String.t()) :: %{running: String.t() | nil, queued: [String.t()]}
  defexport(working(resident_id, session_key), do: Session.working(resident_id, session_key))

  @doc "Runs one turn of a session: the witness's text in, the resident's reply captured and streamed."
  @spec turn(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(turn(resident_id, session_key, text, actor),
    do: turn_admitted(resident_id, session_key, text, actor)
  )

  # A forming resident speaks only in the witness's regression sessions
  # (agathos-daimon#46); woken, the witness's own turns reach them.
  defp turn_admitted(resident_id, session_key, text, actor) do
    with :ok <- admitted(resident_id, session_key, actor),
         do: Session.turn(resident_id, session_key, text, actor)
  end

  # Whether a turn may run (agathos-daimon#46), by the chat's queue or
  # straight: open, anyone the route admits; woken but not yet agreed,
  # the witness alone; forming, the witness in a regression session alone.
  defp admitted(resident_id, session_key, actor) do
    case {AgathosDaimon.admission(resident_id), actor} do
      {:open, _actor} ->
        :ok

      {:witness_only, %{kind: :witness}} ->
        :ok

      {:forming, %{kind: :witness}} ->
        if Kumbukumbu.session_kind(resident_id, session_key) == "regression",
          do: :ok,
          else: {:error, Error.new(:brain_resident_guarded, :brain_turn_forming)}

      {admission, _actor} ->
        {:error, Error.new(:brain_resident_guarded, :brain_turn_guarded, admission: admission)}
    end
  end

  @doc "Wakes the resident in a session with the core's note (spec §6.7, §8): a turn answered under the purpose given, the note captured as a system message ahead of the reply."
  @spec wake(String.t(), String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  @impl Oneiroi.Sunna.Wake
  defexport(wake(resident_id, session_key, note, purpose),
    do: wake_admitted(resident_id, session_key, note, purpose, [])
  )

  @doc "A wake whose answer reaches an audience past the dyad (kumbukumbu#81): her context assembled for it."
  @impl Oneiroi.Sunna.Wake
  defexport(wake_for(resident_id, session_key, note, purpose, opts),
    do:
      wake_admitted(
        resident_id,
        session_key,
        note,
        purpose,
        Keyword.take(opts, [:audience, :sealed])
      )
  )

  # Every wake the platform makes passes here (agathos-daimon#46): a
  # resident formed through the creation flow is woken by nothing but
  # the witness's own words until their first agreement is in force.
  defp wake_admitted(resident_id, session_key, note, purpose, opts) do
    case AgathosDaimon.admission(resident_id) do
      :open ->
        Session.wake(resident_id, session_key, note, purpose, opts)

      admission ->
        {:error, Error.new(:brain_resident_guarded, :brain_wake_guarded, admission: admission)}
    end
  end

  @impl Oneiroi.Sunna.Wake
  @doc "One part of a check-in's note (sunna#28), read from records now; nil for a key the brain does not read."
  defexport(checkin_part(resident_id, key), do: Checkin.part(resident_id, key, Tools.writes()))

  @impl Oneiroi.Sunna.Wake
  @doc "Whether a digest is asked and not yet compiled or failed (sunna#61): the check-in that asked it waits on it."
  defexport(digest_pending?(resident_id), do: Checkin.digest_pending?(resident_id))

  @impl Oneiroi.Sunna.Wake
  @doc "The note for a pass of the memory backfill (sunna#59, brain#96): scenes, domains or people for a past day, from its transcripts' shape and scene rows; :skip when the day gives it nothing."
  defexport(backfill_note(resident_id, pass, day, n, lists),
    do: BackfillNotes.note(resident_id, pass, day, n, lists)
  )

  @doc "Whether each citation named to the house queue is a file that exists (sunna#95): `:ok` or the refusal, naming what was meant."
  @spec queue_document_check(String.t(), [String.t()]) :: :ok | {:error, term()}
  defexport(queue_document_check(household_id, citations),
    do: QueueDocs.check_all(household_id, citations)
  )

  @doc "The citations a task opening names (sunna#95): its slots', links' and given layers' artifacts."
  @spec queue_document_citations(map()) :: [String.t()]
  defexport(queue_document_citations(attrs), do: QueueDocs.of_opening(attrs))

  @doc "A refused document in words, naming what was meant when the house holds it (sunna#95)."
  @spec queue_document_said(Oneiroi.Error.t()) :: String.t()
  defexport(queue_document_said(error), do: QueueDocs.said(error))

  @impl Oneiroi.Sunna.Wake
  @doc "The conversations of a past day the backfill's domains pass has not yet named (sunna#89)."
  defexport(backfill_left(resident_id, day), do: BackfillNotes.left(resident_id, day))

  @impl Oneiroi.Sunna.Wake
  @doc "The backfill's labels pass over a range of past days (kumbukumbu#101): its records labelled again from their turns and their citations, deterministically; `{:ok, changed}`."
  defexport(backfill_labels(resident_id, from_day, to_day),
    do: LabelPropagation.run(resident_id, from_day, to_day)
  )

  @impl Oneiroi.Sunna.Wake
  @doc "The note for a night pass after the scene pass (sunna#57, brain#91): the people or behaviour pass, from the day's scene rows; :skip when the day gives it nothing."
  defexport(night_pass_note(resident_id, pass, day, n),
    do: NightPasses.note(resident_id, pass, day, n)
  )

  @doc "Answers a regression trial (spec §6.4, eunomia#10): the prompt as a turn in a fresh session, with the resident's memory and every tool, the reads real and the writes answered and never recorded; nothing captured, billed under regression. The reply comes back with the trace of the loop's tool calls, for the witness's card alone (eunomia#31)."
  @spec trial(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, Oneiroi.Nisaba.Provider.Result.t(), [Oneiroi.Eunomia.Trial.step()]}
          | {:error, term()}
  @impl Oneiroi.Eunomia.Trial
  defexport(trial(resident_id, model, prompt, actor),
    do: Turn.trial(resident_id, model, prompt, actor)
  )

  @doc "The witness's preview of the next turn of a session (brain#41): the turn's own assembly as a dry run, every section in order with its tokens and reason and its words only where the witness already reads them elsewhere; nothing recorded, nothing billed, no model called."
  @spec preview(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(preview(resident_id, session_key, text, actor),
    do: Preview.preview(resident_id, session_key, text, actor)
  )

  @doc "An adapter's session prefix (spec §8, brain#42): the prompt, the identity files and the contract, by the function the turn's assembly opens with, in parts the runtime can take; records nothing."
  @spec adapter_prefix(String.t(), Oneiroi.Brain.Adapter.opts()) ::
          {:ok, map()} | {:error, term()}
  defexport(adapter_prefix(resident_id, opts), do: Adapter.prefix(resident_id, opts))

  @doc "Starts an adapter's turn with the witness's words and returns its per-turn context (spec §8, brain#42), recording `ContextAssembled` with what it hands over."
  @spec adapter_turn(
          String.t(),
          String.t(),
          String.t(),
          Oneiroi.Actor.t(),
          Oneiroi.Brain.Adapter.opts()
        ) ::
          {:ok, map()} | {:error, term()}
  defexport(adapter_turn(resident_id, session_key, text, actor, opts),
    do: Adapter.turn(resident_id, session_key, text, actor, opts)
  )

  @doc "Drafts an identity file from the witness's prompt under the drafting purpose; returned, not written."
  @spec draft(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, Oneiroi.Brain.Drafting.draft()} | {:error, term()}
  defexport(draft(resident_id, file, prompt, actor),
    do: Drafting.draft(resident_id, file, prompt, actor)
  )

  @doc "The generator (agathos-daimon#39): a draft of every gift's file from the witness's prompt, under drafting; returned, not written."
  @spec generate_gifts(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(generate_gifts(resident_id, prompt, actor),
    do: Creation.generate(resident_id, prompt, actor)
  )

  @doc "Suggested trials (agathos-daimon#42): drafted from her files written so far and the witness's `note`, returned, never kept."
  @spec suggest_trials(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(suggest_trials(resident_id, note, actor),
    do: Creation.suggest_trials(resident_id, note, actor)
  )

  @doc "Get a read (agathos-daimon#40): notes on one gift's draft against its guidance, under drafting, recorded beside the seeds."
  @spec read_gift(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(read_gift(resident_id, file, content, actor),
    do: Creation.read(resident_id, file, content, actor)
  )

  @doc false
  def cast_on_off("on"), do: {:ok, true}
  def cast_on_off("off"), do: {:ok, false}
  # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
  def cast_on_off(other), do: {:error, "is #{inspect(other)}, expected on or off"}

  @doc false
  def cast_pulls_client("github"), do: {:ok, :"Elixir.Oneiroi.Brain.Pulls.GitHub"}
  def cast_pulls_client("fake"), do: {:ok, :"Elixir.Oneiroi.Brain.Pulls.Fake"}
  # oneiroi:allow error_site: a config cast's contract is Oneiroi.Config's {:error, message}
  def cast_pulls_client(other), do: {:error, "is #{inspect(other)}, expected github or fake"}

  @doc "The reacts' vocabulary, `[{emoji, meaning}]`, from REACTIONS.md or the seed (kumbukumbu#56, brain#73)."
  @spec react_vocabulary(String.t()) :: [{String.t(), String.t()}]
  defexport(react_vocabulary(resident_id), do: Reactions.vocabulary(resident_id))

  @doc "Writes the reacts' vocabulary as REACTIONS.md, either party (brain#73)."
  @spec set_react_vocabulary(String.t(), [{String.t(), String.t()}], Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(set_react_vocabulary(resident_id, pairs, actor),
    do: Reactions.set_vocabulary(resident_id, pairs, actor)
  )
end
