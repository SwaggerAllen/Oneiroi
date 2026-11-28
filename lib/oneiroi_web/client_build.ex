defmodule OneiroiWeb.ClientBuild do
  @moduledoc """
  Which build of the client this server serves (apsu#35, the witness,
  2026-11-27: a page kept running the code from before a deploy until it
  was reloaded): a short digest of the built `index.html`, which names
  every hashed asset, so it changes exactly when a deploy changes the
  client. Told to a page when its channel joins; a page that joined
  before a deploy rejoins after the restart, hears a different build,
  and offers a reload. Nil where no client is built (tests, a bare dev
  server), and a page then compares nothing.
  """

  @key {__MODULE__, :id}

  @doc "The built client's digest, read once and kept; nil when none is built."
  @spec id() :: String.t() | nil
  def id do
    case :persistent_term.get(@key, :unread) do
      :unread ->
        id = read()
        :persistent_term.put(@key, id)
        id

      id ->
        id
    end
  end

  # The path is the release's own built client, never a request's.
  # sobelow_skip ["Traversal.FileModule"]
  defp read do
    path = Application.app_dir(:oneiroi, "priv/static/client/index.html")

    case File.read(path) do
      {:ok, html} ->
        :crypto.hash(:sha256, html) |> Base.encode16(case: :lower) |> binary_part(0, 12)

      {:error, _} ->
        nil
    end
  end
end
