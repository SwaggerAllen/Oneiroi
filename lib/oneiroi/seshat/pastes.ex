defmodule Oneiroi.Seshat.Pastes do
  @moduledoc """
  A conversation the witness has with another person, pasted into her
  `human-correspondence/` folder (seshat#65): a new conversation is a new
  document there, and a later paste into the same conversation is
  appended to it under a dated heading (seshat#66). Either is the normal
  document write, as the witness, with a note, so the version, the actor
  and the index are the library's as for any other write.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Leases

  # Her kind, by the name she gave it (seshat#65): the platform does not
  # define it and does not guess another folder when it is missing.
  @folder "human-correspondence"
  @with_max 200
  @title_max 200

  @doc "The folder a pasted conversation lands in."
  def folder, do: @folder

  @doc """
  Pastes a conversation. `%{"path" => p, "text" => t}` appends to the
  conversation at `p`, under `human-correspondence/`; `%{"with" => who,
  "title" => title, "text" => t}` starts a new one, its path made from
  the title (or from whom it is with), never over a document already
  there. `{:ok, %{path, kind, created, changed, indexed}}`.
  """
  def paste(resident_id, attrs, %Actor{kind: :witness} = actor) when is_map(attrs) do
    text = clean(attrs["text"])

    cond do
      text == "" ->
        {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_no_text)}

      is_nil(Kinds.named(resident_id, @folder)) ->
        {:error, Error.new(:seshat_paste_no_kind, :seshat_pastes_no_kind, kind: @folder)}

      present?(attrs["path"]) ->
        extend(resident_id, to_string(attrs["path"]), text, actor)

      true ->
        start(resident_id, attrs, text, actor)
    end
  end

  def paste(_resident_id, _attrs, %Actor{}),
    do: {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_witness_only)}

  # A new conversation: a heading, whom it is with, then the first paste.
  defp start(resident_id, attrs, text, actor) do
    with_whom = line(attrs["with"])
    title = line(attrs["title"])
    title = if title == "", do: "Conversation with #{with_whom}", else: title

    with :ok <- bounded(with_whom, title),
         {:ok, path} <- path_for(title),
         :ok <- not_there(resident_id, path) do
      content = "# #{title}\n\nWith #{with_whom}.\n" <> section(text)
      write(resident_id, path, content, "Pasted a conversation with #{with_whom}", actor, true)
    end
  end

  # An ongoing conversation: what is there, then the new paste under its
  # own dated heading (seshat#66). Read and written in one call, so the
  # client never sends the whole document back.
  defp extend(resident_id, path, text, actor) do
    with :ok <- in_folder(path),
         {:ok, %{content: content}} <- Documents.fetch(resident_id, path) do
      content = String.trim_trailing(content) <> "\n" <> section(text)
      write(resident_id, path, content, "Pasted more of the conversation", actor, false)
    end
  end

  defp write(resident_id, path, content, note, actor, created) do
    with {:ok, result} <- Leases.write(resident_id, path, content, actor, note: note) do
      {:ok, Map.put(result, :created, created)}
    end
  end

  # Each paste is its own section, dated by the server's clock in UTC.
  defp section(text) do
    stamp = Clock.now() |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
    "\n---\n\n## Pasted #{stamp}\n\n#{text}\n"
  end

  defp path_for(title) do
    slug =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 80)
      |> String.trim("-")

    if slug == "",
      do: {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_no_name)},
      else: {:ok, "#{@folder}/#{slug}.md"}
  end

  defp not_there(resident_id, path) do
    case Documents.fetch(resident_id, path) do
      {:error, %Error{kind: :seshat_no_such_document}} -> :ok
      _there -> {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_taken, path: path)}
    end
  end

  defp in_folder(path) do
    if String.starts_with?(path, @folder <> "/"),
      do: :ok,
      else: {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_outside_folder, path: path)}
  end

  defp bounded(with_whom, title) do
    cond do
      with_whom == "" ->
        {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_no_one)}

      String.length(with_whom) > @with_max ->
        {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_with_long)}

      String.length(title) > @title_max ->
        {:error, Error.new(:seshat_paste_invalid, :seshat_pastes_title_long)}

      true ->
        :ok
    end
  end

  defp clean(text) when is_binary(text),
    do: text |> String.replace("\r\n", "\n") |> String.trim()

  defp clean(_other), do: ""

  defp line(v) when is_binary(v), do: v |> String.replace(~r/\s+/u, " ") |> String.trim()
  defp line(_other), do: ""

  defp present?(v), do: is_binary(v) and String.trim(v) != ""
end
