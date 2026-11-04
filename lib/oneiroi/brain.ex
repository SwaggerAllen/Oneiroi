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
      Oneiroi.AgathosDaimon,
      Oneiroi.Ethos,
      Oneiroi.Eunomia,
      Oneiroi.Glitnir,
      Oneiroi.HuginnMuninn,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba,
      Oneiroi.Proteus,
      Oneiroi.Seshat,
      Oneiroi.SimaQian,
      Oneiroi.Sunna,
      Oneiroi.Xenia,
      Jason,
      # The oracle's worker (brain#49), as every system with a worker has.
      Oban
    ],
    exports: [Error, Session, Turn, Tools, Compaction, Drafting, FixtureRun]

  alias Oneiroi.Brain.Adapter
  alias Oneiroi.Brain.Drafting
  alias Oneiroi.Brain.FreeTime
  alias Oneiroi.Brain.Preview
  alias Oneiroi.Brain.Session
  alias Oneiroi.Brain.Tools
  alias Oneiroi.Brain.Turn

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:chat_model, "BRAIN_CHAT_MODEL",
       default: "openai/gpt-4o-mini",
       usage:
         "the chat model until the witness's pin arrives with regression (spec §6.4): a placeholder chosen for being cheap and widely served, not measured"},
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
      {:turn_timeout_ms, "BRAIN_TURN_TIMEOUT_MS",
       cast: :integer,
       default: "180000",
       tag: :bound,
       usage:
         "how long a caller waits on a session process for a turn before giving up; a bound above the port's own timeout"}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:brain_turn_failed,
       "the turn did not complete: the witness's words were kept and no reply was captured (brain#45)",
       remedy:
         "the provider failure is recorded as a capture failure on the session; send the message again"},
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
      {:brain_oracle_silent, "the oracle's reading answered no words",
       remedy: "ask the question again; it may need narrower sources"},
      {:brain_summary_empty, "the model answered the compaction with no words",
       remedy: "nothing was compacted; the next turn tries again"},
      {:brain_path_invalid,
       "a path in the source or the repository is relative and plain: no .., no absolute path, no .git or build output",
       remedy: "name the file from the root, as the listing shows it"},
      {:brain_path_absent, "nothing is at that path", remedy: "list the folder first"},
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
    do: [{:brain_registry, :local}, {:brain_sessions, :local}, {:brain_turns, :local}]

  # The oracle's reads (brain#49): on demand, no cron.
  @impl Oneiroi.Component
  def oban_queues, do: [{:brain_oracle, []}]

  @impl Oneiroi.Component
  def pubsub_topics, do: [:session]

  @impl Oneiroi.Component
  def children do
    [
      {Registry, keys: :unique, name: :brain_registry},
      {DynamicSupervisor, name: :brain_sessions, strategy: :one_for_one},
      # The turns a session runs off its own process (brain#45).
      {Task.Supervisor, name: :brain_turns}
    ]
  end

  @doc "Free time remembered (brain#53): the latest runs, newest first, with the conversation each ran in, its turns, and the receipts of what it made."
  @spec free_time_history(String.t(), pos_integer()) :: [map()]
  defexport(free_time_history(resident_id, limit),
    do: FreeTime.history(resident_id, limit, Tools.writes())
  )

  @doc """
  Takes the witness's message under the client's ref and answers at once
  (brain#45): `running`, `queued` with how many wait ahead, or
  `duplicate` when that ref was taken before. The turn's outcome arrives
  on the session topic.
  """
  @spec submit(String.t(), String.t(), String.t(), Oneiroi.Actor.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(submit(resident_id, session_key, text, actor, ref),
    do: Session.submit(resident_id, session_key, text, actor, ref)
  )

  @doc "Runs one turn of a session: the witness's text in, the resident's reply captured and streamed."
  @spec turn(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(turn(resident_id, session_key, text, actor),
    do: Session.turn(resident_id, session_key, text, actor)
  )

  @doc "Wakes the resident in a session with the core's note (spec §6.7, §8): a turn answered under the purpose given, the note captured as a system message ahead of the reply."
  @spec wake(String.t(), String.t(), String.t(), atom()) :: {:ok, map()} | {:error, term()}
  @impl Oneiroi.Sunna.Wake
  defexport(wake(resident_id, session_key, note, purpose),
    do: Session.wake(resident_id, session_key, note, purpose)
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
end
