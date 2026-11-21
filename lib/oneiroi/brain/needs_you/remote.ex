defmodule Oneiroi.Brain.NeedsYou.Remote do
  @moduledoc """
  A public backup remote (sima-qian#65; the witness, 2026-11-21: "worth
  checking so we can warn the user"): while her backup's host says the
  repository is public, it waits on him, on Settings, where the remote is
  set. Backups go on whatever he decides; until F80 encrypts what they
  carry, anyone can read them. A host that cannot be asked is not a
  warning.
  """
  @behaviour Oneiroi.Brain.NeedsYou.Source

  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.NeedsYou.Entry

  @doc "The entry kind."
  @spec kind() :: String.t()
  def kind, do: "remote_public"

  @impl true
  def stages, do: [%{kind: kind(), screen: "settings"}]

  @impl true
  def entries(resident_id) do
    case AgathosDaimon.fetch(resident_id) do
      {:ok, %{remote_visibility: "public", remote_url: url, remote_checked_at: at}}
      when is_binary(url) ->
        [
          %Entry{
            kind: kind(),
            ref: "remote",
            since: at,
            screen: "settings",
            about: %{what: "Her backup repository is public: " <> shown(url)}
          }
        ]

      _private_or_unknown ->
        []
    end
  end

  # The address without any credential written into it.
  defp shown(url), do: String.replace(url, ~r{//[^/@]*@}, "//")
end
