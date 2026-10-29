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
  @type failure :: {:transport, term()} | {:rejected, term()}

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
end
