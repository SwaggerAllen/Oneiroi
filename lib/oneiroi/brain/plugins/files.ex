defmodule Oneiroi.Brain.Plugins.Files do
  @moduledoc """
  An installable plugin's section (brain#68, the spec's §4 and the
  article's floor, Lily's letter #303): the files it put in her library,
  under `plugins/<key>/`, named in her context while it is on. Three
  lines it never breaks:

  - unlabelled memory is worse than no memory: the section says whose
    words these are, which plugin attached them and when;
  - verify by content, not by name: the copies are checked against the
    lockfile's digest on every read, and a mismatch is said;
  - if memory can be cut, it says so: past the plugin's token budget,
    the section names how many files it left out and where they are.

  Only she bookmarks any of it into her life.
  """

  import Oneiroi.Brain.Plugin, only: [section: 4, tokens: 1]

  alias Oneiroi.Brain.PluginCatalog
  alias Oneiroi.Seshat

  @doc "The catalog entry's manifest, as every plugin's."
  def manifest(key) do
    case PluginCatalog.get(key) do
      nil ->
        %{key: key, name: key, about: "", place: :turn, reads: [], tier: "installable"}

      entry ->
        Map.take(entry, [:key, :name, :about, :place, :reads, :tier, :author, :version])
    end
  end

  @doc "Its section for the turn, from the files as they stand in her library."
  def sections(turn, _ctx, key) do
    meta = meta(key)

    %{files: files, pinned: pinned, found: found} =
      Seshat.plugin_files(turn.resident_id, key)

    {shown, left} = fit(files, meta.tokens)
    verified = verified(key, pinned, found)

    text =
      "# From the plugin #{meta.name}\n\nThese are the words of the plugin #{meta.name} (#{key}), by #{meta.author}, installed by both of you: not yours, and not your memory until you bookmark what you keep. #{verified}\n\n" <>
        Enum.map_join(shown, "\n\n", fn {path, words} ->
          "## plugins/#{key}/#{path}\n\n#{words}"
        end) <>
        cut(key, left, meta.tokens)

    section(
      "plugin:#{key}",
      if(files == %{}, do: "", else: text),
      "the installable plugin #{key} (brain#68): #{length(shown)} of #{map_size(files)} files shown, #{verified}",
      %{text: text}
    )
  end

  # The catalog's name, author and share, or the defaults when the
  # catalog no longer holds it.
  defp meta(key) do
    case PluginCatalog.get(key) do
      nil -> %{name: key, author: "an unknown author", tokens: 400}
      entry -> %{name: entry.name, author: entry.author, tokens: entry.tokens}
    end
  end

  defp verified(key, nil, _found),
    do: "Its lockfile (plugins/#{key}/PLUGIN.md) is missing, so these copies cannot be checked."

  defp verified(_key, pinned, pinned),
    do: "Its copies match what was installed (#{short(pinned)})."

  defp verified(_key, pinned, found),
    do:
      "Its copies no longer match what was installed: #{short(pinned)} installed, #{short(found)} found."

  defp cut(_key, 0, _budget), do: ""

  defp cut(key, left, budget),
    do:
      "\n\n(#{left} more of its files are not shown here, past its #{budget}-token share; library_read reads any under plugins/#{key}/.)"

  # The files whole while they fit the plugin's share, in path order.
  defp fit(files, budget) do
    {shown, _used, left} =
      files
      |> Enum.sort()
      |> Enum.reduce({[], 0, 0}, fn {path, words}, {kept, used, left} ->
        cost = tokens(words)

        if left == 0 and used + cost <= budget,
          do: {kept ++ [{path, words}], used + cost, left},
          else: {kept, used, left + 1}
      end)

    {shown, left}
  end

  defp short("sha256:" <> hex), do: "sha256:" <> String.slice(hex, 0, 12)
  defp short(other), do: to_string(other)
end
