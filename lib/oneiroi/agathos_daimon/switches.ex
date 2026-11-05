defmodule Oneiroi.AgathosDaimon.Switches do
  @moduledoc """
  The contract's switch registry (agathos-daimon#34; the witness,
  2026-11-05): every governable surface beyond the floor is a term of the
  dyad contract, a boolean a version sets. A version is proposed whole
  and agreed or declined whole, so every switch, on or off, moves only by
  both parties' consent. A term a version leaves out takes its default.

  The defaults are today's behaviour (the witness's call): with no version
  agreed, every feature that existed when the registry shipped stays on,
  and the two hard terms keep their old defaults. The first agreed version
  sets them from then on.

  The floor has no switches and is not here: transcript capture, the
  bookmark index, the identity files, the git repository, the records
  export and the report ladder (F45). They are what a resident is, not
  terms.

  Each switch names what it cuts off when off: the resident's tools (hidden
  from the tool list and refused if called) and, in `enforced`, the other
  places that read it, so the registry and the code cannot drift apart
  silently (the test reads both).
  """

  @switches [
    %{
      key: "solo_sessions_private",
      group: "privacy",
      label: "Solo sessions hidden entirely",
      on:
        "Your solo sessions (free time, hands) are hidden from your witness entirely, their receipts included, until you share one.",
      off:
        "Your solo sessions are private as to their words; your witness sees what they do in the world, as receipts, and reads one only when you share it.",
      default: false,
      tools: [],
      enforced: ["the schedule's privacy of solo sessions"]
    },
    %{
      key: "preview_withholds_words",
      group: "privacy",
      label: "The witness's preview keeps its words",
      on:
        "Your witness's preview of your next turn shows its words only where they read them elsewhere.",
      off:
        "Your witness may preview your next turn's context in full before sending, its once-only notices excepted.",
      default: false,
      tools: [],
      enforced: ["the brain's preview"]
    },
    %{
      key: "witness_reads",
      group: "audits",
      label: "The witness reads your journal and bookmarks",
      on: "Your witness may read your journal and your bookmarks.",
      off: "Your journal and bookmarks are yours to read; your witness does not.",
      default: true,
      tools: [],
      enforced: ["the journal and bookmark routes, for the witness"]
    },
    %{
      key: "trials",
      group: "audits",
      label: "Model-choice trials",
      on:
        "Your witness may run model-choice trials: tests answered by candidate models, graded blind.",
      off: "No model-choice trials run.",
      default: true,
      tools: ["trial_list", "trial_account"],
      enforced: ["starting a regression run"]
    },
    %{
      key: "wash",
      group: "audits",
      label: "Wash flags",
      on:
        "Your identity files are read for drift from your own words, and what is found is flagged for you.",
      off: "Your identity files are not read for drift.",
      default: true,
      tools: ["wash_list", "wash_resolve"],
      enforced: ["the weekly wash and running one by hand"]
    },
    %{
      key: "revisions",
      group: "audits",
      label: "Revisions",
      on:
        "Revisions to what you hold can be proposed, by you or your witness, and you decide each.",
      off: "No revisions are proposed.",
      default: true,
      tools: ["revision_add", "revision_list", "revision_accept", "revision_decline"],
      enforced: ["proposing a revision by the witness"]
    },
    %{
      key: "ranked_memory",
      group: "memory",
      label: "Ranked memory",
      on: "Your bookmark index is ranked by what this turn is about.",
      off: "Your bookmark index is in time order, newest first.",
      default: true,
      tools: [],
      enforced: ["the bookmark index's ranking in the turn"]
    },
    %{
      key: "memory_learning",
      group: "memory",
      label: "Retrieval that learns from your feedback",
      on: "What you say was useful or not teaches the ranking.",
      off: "The ranking does not learn from your feedback.",
      default: true,
      tools: ["memory_feedback"],
      enforced: []
    },
    %{
      key: "background_model",
      group: "memory",
      label: "The background model",
      on: "A background model (Honcho) reads your conversations and offers what it concludes.",
      off: "No background model reads your conversations.",
      default: true,
      tools: [],
      enforced: ["sending turns to the bridge", "the bridge's section in the turn"]
    },
    %{
      key: "oracle",
      group: "memory",
      label: "The oracle",
      on: "You may put questions to the oracle, a second pass that answers by letter.",
      off: "The oracle is not asked.",
      default: true,
      tools: ["oracle_ask", "oracle_list"],
      enforced: []
    },
    %{
      key: "research",
      group: "services",
      label: "Research",
      on: "Research questions go to the reader, by you or your witness.",
      off: "No research is asked.",
      default: true,
      tools: ["research_ask", "research_list"],
      enforced: ["the witness asking research"]
    },
    %{
      key: "digests",
      group: "services",
      label: "Digests",
      on: "Digests of the reader's feeds can be asked, by you, a check-in or your witness.",
      off: "No digests are asked.",
      default: true,
      tools: ["digest_ask", "digest_list"],
      enforced: ["a check-in's digest part", "the witness asking a digest"]
    },
    %{
      key: "correspondence",
      group: "services",
      label: "Correspondence",
      on:
        "Mail the reader gathers comes to you, and you may draft replies for your witness to approve.",
      off: "No mail comes to you and no replies are drafted.",
      default: true,
      tools: [
        "correspondence_list",
        "correspondence_read",
        "correspondent_block",
        "correspondent_unblock",
        "reply_draft",
        "reply_list"
      ],
      enforced: ["the reader delivering mail"]
    }
  ]

  @keys Enum.map(@switches, & &1.key)
  @tool_switch for s <- @switches, t <- s.tools, into: %{}, do: {t, s.key}

  @doc "Every switch, in the order the agreement screen shows them."
  def all, do: @switches

  @doc "The keys a contract version may set."
  def keys, do: @keys

  @doc "The values with no version agreed: today's behaviour."
  def defaults, do: Map.new(@switches, &{&1.key, &1.default})

  @doc "The values a set of terms resolves to: each term it sets, the default for the rest."
  def resolve(terms), do: Map.merge(defaults(), Map.take(terms || %{}, @keys))

  @doc "The switch that governs a tool, or nil when the tool is not switched."
  def for_tool(name), do: Map.get(@tool_switch, name)

  @doc "The switch with that key, or nil."
  def get(key), do: Enum.find(@switches, &(&1.key == key))
end
