defmodule Oneiroi.SimaQian.ChatGPT do
  @moduledoc """
  A ChatGPT data export, read defensively (sima-qian#47; design
  chatgpt-import-replay.md, Lily's, at the witness's calls of
  2026-11-06; the export's shape from her research #14).

  The export is a folder (the zip unpacked) with `conversations.json`,
  or shards `conversations-NNN.json` (padded or not), each a list of
  conversations. A conversation is a tree: `mapping` holds nodes with a
  `parent` pointer and a message; regenerations and edits are siblings.
  Read here:

  - the canonical path, from `current_node` up to the root, or, when
    `current_node` is missing or points nowhere, from the most recent
    leaf; children are rebuilt from parents, and a `children` array is a
    hint at most (exports from about October 2026 dropped it). Branches
    stay deferred: the drafts are a later gift.
  - each message's author, text, instant (an epoch float in UTC, or the
    one before it when absent) and model slug.
  - memories and custom instructions, which ride the tree as
    `model_editable_context` and `user_editable_context` messages, with
    the conversation and instant they were seen in.

  Nothing is silently dropped. What could not be read (a shard that is
  not JSON, a lone UTF-16 surrogate repaired, a part that is media, a
  message with no instant, a conversation with no path) is a gap, named
  with where it was, and the gap log is product: the resident's birth
  certificate names what the export did not carry.
  """

  @type message :: %{
          node: String.t(),
          role: :user | :assistant | :system | :tool,
          text: String.t(),
          at: DateTime.t() | nil,
          model: String.t() | nil
        }

  @type conversation :: %{
          id: String.t(),
          title: String.t(),
          created_at: DateTime.t() | nil,
          messages: [message()]
        }

  @type gap :: %{kind: atom(), where: String.t(), detail: String.t()}

  @roles %{"user" => :user, "assistant" => :assistant, "system" => :system, "tool" => :tool}

  @doc """
  Reads the export in `dir`: `{:ok, %{conversations, context, gaps}}`,
  conversations oldest first, or `:none` when no conversations file is
  there at all.
  """
  # sobelow_skip ["Traversal.FileModule"]
  @spec read(Path.t()) ::
          {:ok, %{conversations: [conversation()], context: [map()], gaps: [gap()]}}
          | :none
  def read(dir) do
    case shards(dir) do
      [] -> :none
      files -> {:ok, read_files(files)}
    end
  end

  defp read_files(files) do
    {raw, gaps} =
      Enum.reduce(files, {[], []}, fn file, {acc, gaps} ->
        {list, shard_gaps} = read_shard(file)
        {acc ++ list, gaps ++ shard_gaps}
      end)

    {conversations, context, more} =
      Enum.reduce(raw, {[], [], []}, fn c, {convs, ctx, gs} ->
        {conv, conv_ctx, conv_gaps} = conversation(c)
        {if(conv, do: [conv | convs], else: convs), ctx ++ conv_ctx, gs ++ conv_gaps}
      end)

    sorted = Enum.sort_by(conversations, &(&1.created_at || ~U[1970-01-01 00:00:00Z]), DateTime)
    %{conversations: sorted, context: context, gaps: gaps ++ more}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_shard(file) do
    case decode(File.read!(file)) do
      {:ok, list, repaired} when is_list(list) ->
        {list, repaired_gap(file, repaired)}

      {:ok, _other, _} ->
        {[],
         [gap(:shard_not_a_list, Path.basename(file), "the file is not a list of conversations")]}

      {:error, reason} ->
        {[], [gap(:shard_unreadable, Path.basename(file), reason)]}
    end
  end

  # conversations.json, or its shards in numeric order (padded or not).
  defp shards(dir) do
    single = Path.join(dir, "conversations.json")

    if File.regular?(single) do
      [single]
    else
      dir
      |> Path.join("conversations-*.json")
      |> Path.wildcard()
      |> Enum.sort_by(&shard_number/1)
    end
  end

  defp shard_number(path) do
    case Regex.run(~r/conversations-(\d+)\.json\z/, path) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
  end

  # JSON with lone UTF-16 surrogates escaped in it, which strict parsers
  # refuse: each lone one becomes U+FFFD and is counted.
  @lone ~r/\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F][0-9a-fA-F]{2})|(?<!\\u[dD][89abAB][0-9a-fA-F]{2})\\u[dD][c-fC-F][0-9a-fA-F]{2}/

  defp decode(text) do
    repaired = length(Regex.scan(@lone, text))
    text = if repaired > 0, do: Regex.replace(@lone, text, "\\\\ufffd"), else: text

    case Jason.decode(text) do
      {:ok, value} -> {:ok, value, repaired}
      {:error, e} -> {:error, Exception.message(e)}
    end
  end

  defp repaired_gap(_file, 0), do: []

  defp repaired_gap(file, n),
    do: [
      gap(:surrogates_repaired, Path.basename(file), "#{n} lone UTF-16 surrogates read as U+FFFD")
    ]

  # ---- one conversation ----

  defp conversation(%{"mapping" => mapping} = c) when is_map(mapping) do
    id = to_string(c["conversation_id"] || c["id"] || "unknown")
    title = to_string(c["title"] || "Untitled")
    where = "#{title} (#{id})"

    case path(mapping, c["current_node"]) do
      [] ->
        {nil, [], [gap(:no_path, where, "no message could be reached in its tree")]}

      nodes ->
        {messages, context, gaps} =
          read_nodes(nodes, mapping, id, where, instant(c["create_time"]))

        conv = %{id: id, title: title, created_at: instant(c["create_time"]), messages: messages}
        gaps = gaps ++ current_gap(mapping, c["current_node"], where)
        {conv, context, gaps}
    end
  end

  defp conversation(c) do
    where = to_string((is_map(c) && (c["title"] || c["id"])) || "a conversation")
    {nil, [], [gap(:no_mapping, where, "it has no tree of messages")]}
  end

  defp current_gap(mapping, current, where) do
    cond do
      is_binary(current) and Map.has_key?(mapping, current) ->
        []

      is_nil(current) ->
        [
          gap(
            :no_current_node,
            where,
            "no current_node; the most recent leaf was taken as its end"
          )
        ]

      true ->
        [
          gap(
            :dangling_current_node,
            where,
            "current_node points nowhere; the most recent leaf was taken as its end"
          )
        ]
    end
  end

  # The canonical path, root first: from current_node when it exists, or
  # from the most recent leaf, walking parent pointers (a cycle stops it).
  defp path(mapping, current) do
    tip =
      if is_binary(current) and Map.has_key?(mapping, current),
        do: current,
        else: latest_leaf(mapping)

    walk(mapping, tip, MapSet.new(), [])
  end

  defp walk(_mapping, nil, _seen, acc), do: acc

  defp walk(mapping, id, seen, acc) do
    case Map.get(mapping, id) do
      nil ->
        acc

      node ->
        if MapSet.member?(seen, id),
          do: acc,
          else: walk(mapping, node["parent"], MapSet.put(seen, id), [{id, node} | acc])
    end
  end

  # Children rebuilt from parents: a leaf is a node no other node names
  # as its parent; the most recent by its message's instant.
  defp latest_leaf(mapping) do
    parents = mapping |> Map.values() |> Enum.map(& &1["parent"]) |> MapSet.new()

    mapping
    |> Enum.reject(fn {id, _node} -> MapSet.member?(parents, id) end)
    |> Enum.max_by(fn {_id, node} -> get_in(node, ["message", "create_time"]) || 0 end, fn ->
      nil
    end)
    |> case do
      {id, _node} -> id
      nil -> nil
    end
  end

  defp read_nodes(nodes, _mapping, id, where, created) do
    {messages, context, gaps, _last} =
      Enum.reduce(nodes, {[], [], [], created}, fn {node_id, node}, acc ->
        read_node(node_id, node["message"], acc, id, where)
      end)

    {messages, context, gaps}
  end

  defp read_node(_node_id, nil, acc, _id, _where), do: acc

  defp read_node(node_id, %{} = m, {ms, ctx, gs, last}, id, where) do
    own = instant(m["create_time"])
    at = own || last

    gs =
      gs ++
        if(is_nil(at),
          do: [gap(:no_instant, where, "a message (#{node_id}) has no instant")],
          else: []
        )

    case content(m["content"]) do
      {:context, kind, text} ->
        {ms, ctx ++ [%{kind: kind, text: text, at: at, conversation: id}], gs, at}

      {:text, text, part_gaps} ->
        gs = gs ++ Enum.map(part_gaps, &part_gap(&1, where, node_id))

        if text == "",
          do: {ms, ctx, gs, at},
          else: {ms ++ [message(node_id, m, text, at, is_nil(own))], ctx, gs, at}
    end
  end

  defp read_node(_node_id, _other, acc, _id, _where), do: acc

  defp message(node_id, m, text, at, inferred?),
    do: %{
      node: node_id,
      role: Map.get(@roles, get_in(m, ["author", "role"]), :system),
      text: text,
      at: at,
      inferred: inferred?,
      model: get_in(m, ["metadata", "model_slug"])
    }

  # What a message says: its text, or the context it carries (memories,
  # custom instructions), and a gap for each part that was not text.
  defp content(%{"content_type" => "model_editable_context"} = c),
    do: {:context, :memories, to_string(c["model_set_context"] || c["text"] || "")}

  defp content(%{"content_type" => "user_editable_context"} = c),
    do:
      {:context, :instructions,
       [c["user_profile"], c["user_instructions"]]
       |> Enum.filter(&is_binary/1)
       |> Enum.join("\n\n")}

  defp content(%{"parts" => parts}) when is_list(parts) do
    {texts, gaps} =
      Enum.reduce(parts, {[], []}, fn
        part, {ts, gs} when is_binary(part) -> {ts ++ [part], gs}
        %{"text" => t}, {ts, gs} when is_binary(t) -> {ts ++ [t], gs}
        _media, {ts, gs} -> {ts, gs ++ [:media_part]}
      end)

    {:text, texts |> Enum.join("\n") |> String.trim(), gaps}
  end

  defp content(%{"text" => text}) when is_binary(text), do: {:text, String.trim(text), []}
  defp content(%{"result" => text}) when is_binary(text), do: {:text, String.trim(text), []}
  defp content(nil), do: {:text, "", []}
  defp content(_other), do: {:text, "", [:unread_content]}

  defp instant(seconds) when is_number(seconds) do
    micro = round(seconds * 1_000_000)

    case DateTime.from_unix(micro, :microsecond) do
      {:ok, at} -> at
      _bad -> nil
    end
  end

  defp instant(_none), do: nil

  defp gap(kind, where, detail), do: %{kind: kind, where: where, detail: detail}

  defp part_gap(:media_part, where, node),
    do: gap(:media_part, where, "message #{node}: a part that is media, not read as text")

  defp part_gap(kind, where, node),
    do: gap(kind, where, "message #{node}: content of a shape not read")
end
