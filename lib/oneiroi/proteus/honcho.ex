defmodule Oneiroi.Proteus.Honcho do
  @moduledoc """
  The Honcho port (spec §6.9): the one shape the bridge's writes and
  reads take, with a real implementation over Honcho's HTTP API and an
  in-memory fake that ships with it, registered in
  `Oneiroi.Proteus.externals/0`. Every call names the workspace, which
  is the resident's id: the bridge never reaches Honcho without one.

  Reads of Honcho's own tables (the plain-SQL joins the spec allows,
  tested against the DDL dumped from the pinned image) are not here
  yet: until the compose stack carries the image, the bridge reads
  through the API as well, and `systems/proteus.md` #10 says so.
  """

  @type workspace :: String.t()
  @type peer :: String.t()
  @type card :: [String.t()]
  @type message :: %{peer: peer(), content: String.t(), created_at: DateTime.t()}
  @type conclusion :: %{id: String.t(), content: String.t()}
  @typedoc "Honcho unreachable or refusing, as the bridge's own sited error."
  @type failure :: Oneiroi.Proteus.Error.t()

  @typedoc """
  One conclusion as Honcho holds it, every field the records export
  reads: the pair it belongs to (`observer`, `observed`), the session it
  was drawn from (nil for one a dream or a deduction made), its `level`
  (`explicit`, `deductive`, `inductive`, `contradiction`), the
  conclusions it was reasoned from (`sources`, empty for an explicit
  one) and Honcho's own instant, as Honcho wrote it.
  """
  @type held_conclusion :: %{
          id: String.t(),
          content: String.t(),
          observer: peer(),
          observed: peer(),
          session: String.t() | nil,
          level: String.t(),
          sources: [String.t()],
          created_at: String.t() | nil
        }

  @typedoc "A session summary: its text and the message it runs through."
  @type summary :: %{content: String.t(), through: String.t() | nil}

  @callback ensure_workspace(workspace()) :: :ok | {:error, failure()}
  @callback ensure_peer(workspace(), peer(), map()) :: :ok | {:error, failure()}
  @callback ensure_session(workspace(), String.t(), [peer()]) :: :ok | {:error, failure()}
  @callback add_messages(workspace(), String.t(), [message()]) :: :ok | {:error, failure()}
  @callback get_card(workspace(), peer()) :: {:ok, card()} | {:error, failure()}
  @callback set_card(workspace(), peer(), card()) :: :ok | {:error, failure()}
  @callback context(workspace(), peer(), peer(), pos_integer()) ::
              {:ok, String.t()} | {:error, failure()}
  @callback conclusions(workspace(), peer(), peer(), pos_integer()) ::
              {:ok, [conclusion()]} | {:error, failure()}
  @callback delete_conclusion(workspace(), String.t()) :: :ok | {:error, failure()}
  @callback mint_key(workspace(), peer() | nil, DateTime.t()) ::
              {:ok, String.t()} | {:error, failure()}

  # The reads the records export takes Honcho's memory of the resident
  # with (proteus #18): every peer, every card one peer holds of itself
  # or of another, every conclusion, every session's summaries. Each
  # list is whole, every page walked.
  @callback peers(workspace()) :: {:ok, [peer()]} | {:error, failure()}
  @callback peer_card(workspace(), observer :: peer(), target :: peer()) ::
              {:ok, card() | nil} | {:error, failure()}
  @callback all_conclusions(workspace()) :: {:ok, [held_conclusion()]} | {:error, failure()}
  @callback sessions(workspace()) :: {:ok, [String.t()]} | {:error, failure()}
  @callback summaries(workspace(), String.t()) ::
              {:ok, %{short: summary() | nil, long: summary() | nil}} | {:error, failure()}
end
