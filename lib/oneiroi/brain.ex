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

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Oneiroi.AgathosDaimon,
      Oneiroi.Kumbukumbu,
      Oneiroi.Nisaba
    ],
    exports: [Error, Session, Turn]

  alias Oneiroi.Brain.Session

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:chat_model, "BRAIN_CHAT_MODEL",
       default: "openai/gpt-4o-mini",
       usage:
         "the chat model until the steward's pin arrives with regression (spec §6.4): a placeholder chosen for being cheap and widely served, not measured"},
      {:transcript_messages, "BRAIN_TRANSCRIPT_MESSAGES",
       cast: :integer,
       default: "40",
       tag: :bound,
       usage:
         "how many of the session's last messages a turn is shown as its live transcript; a bound until compaction lands"},
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
      {:brain_turn_failed, "the turn did not complete and nothing was captured for it",
       remedy:
         "the provider failure is recorded as a capture failure on the session; retry the message"}
    ]
  end

  @impl Oneiroi.Component
  def processes, do: [{:brain_registry, :local}, {:brain_sessions, :local}]

  @impl Oneiroi.Component
  def pubsub_topics, do: [:session]

  @impl Oneiroi.Component
  def children do
    [
      {Registry, keys: :unique, name: :brain_registry},
      {DynamicSupervisor, name: :brain_sessions, strategy: :one_for_one}
    ]
  end

  @doc "Runs one turn of a session: the steward's text in, the resident's reply captured and streamed."
  @spec turn(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(turn(resident_id, session_key, text, actor),
    do: Session.turn(resident_id, session_key, text, actor)
  )
end
