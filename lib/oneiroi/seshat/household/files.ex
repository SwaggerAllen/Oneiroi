defmodule Oneiroi.Seshat.Household.Files do
  @moduledoc """
  The household repository's files (seshat#59), the bottom layer: the
  repository at its head, a thread and its replies read from it, the
  documents on the shelf, paths and frontmatter, the commit, and the
  lock that orders the household's writes. It calls no other
  `Household` module.

  Its public functions are reached through `Oneiroi.Seshat.Household`,
  which carries their docs.
  """

  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Notices
  alias Oneiroi.Apsu.PubSub
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.SimaQian.Repos

  @contract "CONTRACT.md"
  @trunk "trunk.md"
  @title_max 200
  @text_max 64_000

  # ---- the repository at its head (sima-qian#57) ----

  @doc false
  # The household's repository at its head (sima-qian#57): one tree call,
  # the files read from it through the blob cache.
  def view(household_id) do
    repo = {:household, household_id}
    with {:ok, files} <- Repos.snapshot(repo), do: {:ok, %{repo: repo, files: files}}
  end

  @doc false
  def file(view, path), do: Repos.at(view.repo, view.files, path)

  @doc false
  def has?(view, path), do: Map.has_key?(view.files, path)

  # ---- a document's draft (seshat#83) ----

  @doc false
  # The commit that last changed a document: its draft.
  def doc_commit(view, path) do
    case Repos.history(view.repo, path, 1) do
      {:ok, [%{commit: sha} | _]} -> sha
      _none -> nil
    end
  end

  @doc false
  def draft_at(nil), do: ""

  def draft_at(sha), do: ", draft #{short(sha)}"

  @doc false
  def short(sha), do: String.slice(sha, 0, 12)

  @doc false
  def optional(_key, nil), do: []

  def optional(key, value), do: [{key, value}]

  # ---- files ----

  @doc false
  def thread_ids(view) do
    for path <- Map.keys(view.files),
        [_, id] <- [Regex.run(~r{\Athreads/([^/]+)/trunk\.md\z}, path)],
        do: id
  end

  @doc false
  def thread_summary(view, id, ballots) do
    thread = "threads/" <> id
    {:ok, t} = load_thread(view, thread)
    last = List.last(t.replies)
    ballot = ballots[thread]

    %{
      kind: "thread",
      path: thread,
      title: t.trunk.meta["title"],
      by: t.trunk.meta["by"],
      posted_at: t.trunk.meta["posted_at"],
      replies: length(t.replies),
      last_reply_at: last && last.meta["at"],
      ballot: ballot && Map.take(ballot, [:number, :closes_at, :closed_at, :passed]),
      ids: ids(t)
    }
  end

  @doc false
  def ids(t), do: [t.trunk.meta["by_id"] | Enum.map(t.replies, & &1.meta["by_id"])]

  @doc false
  def documents(view) do
    for kind <- Kinds.household(),
        not Kinds.container?(kind),
        path <- Repos.under(view.files, kind.folder),
        name = Path.basename(path),
        in_folder?(kind, path),
        name != Kinds.descriptor_name() do
      {meta, _} = view |> file(path) |> to_string() |> frontmatter()

      %{
        kind: kind.kind,
        path: path,
        title: meta["title"] || name,
        by: meta["by"],
        by_id: meta["by_id"],
        posted_at: meta["posted_at"],
        edited_by: meta["edited_by"],
        edited_by_id: meta["edited_by_id"],
        edited_at: meta["edited_at"],
        source: meta["source"],
        mode: meta["mode"],
        terms: meta["terms"],
        unpromoted_at: meta["unpromoted_at"]
      }
    end
  end

  # A document sits in its kind's folder; a witness's, one deeper, in the
  # folder named for them (seshat#81).
  defp in_folder?(%{kind: "human"}, path), do: length(Path.split(path)) == 3

  # A promoted copy keeps her path under her folder (seshat#99).
  defp in_folder?(%{kind: "shared"}, path), do: length(Path.split(path)) >= 3

  # A task's index document is one deeper, under its project (seshat#104).
  defp in_folder?(%{kind: "task"}, path), do: length(Path.split(path)) == 3

  defp in_folder?(kind, path), do: Path.dirname(path) == kind.folder

  @doc false
  def load_thread(view, thread) do
    trunk = Path.join(thread, @trunk)

    if has?(view, trunk) do
      replies = replies(view, thread)
      {meta, body} = view |> file(trunk) |> to_string() |> frontmatter()

      {:ok,
       %{trunk: %{path: Path.join(thread, @trunk), meta: meta, body: body}, replies: replies}}
    else
      no_thread(thread)
    end
  end

  defp replies(view, thread) do
    for path <- Repos.under(view.files, Path.join(thread, "replies")) do
      {meta, body} = view |> file(path) |> to_string() |> frontmatter()
      %{path: path, meta: meta, body: body}
    end
  end

  @doc false
  # The document a document post is on (seshat#83), as it stands now:
  # its path, its latest draft and its words; nil for any other thread.
  def posted_doc(view, %{trunk: %{meta: %{"doc" => path}}}) do
    text = file(view, path)
    {_meta, body} = frontmatter(to_string(text))
    %{path: path, commit: doc_commit(view, path), content: body, present: is_binary(text)}
  end

  def posted_doc(_view, _t), do: nil

  @doc false
  # The document posts on a document (seshat#83): where its feedback is.
  def discussed(view, path) do
    for id <- thread_ids(view),
        thread = "threads/" <> id,
        {:ok, t} <- [load_thread(view, thread)],
        t.trunk.meta["doc"] == path,
        do: %{path: thread, title: t.trunk.meta["title"], replies: length(t.replies)}
  end

  @doc false
  def thread_text(thread, t, ballot, doc) do
    head =
      "# #{t.trunk.meta["title"]}\n#{thread}, posted by #{t.trunk.meta["by"]} at #{t.trunk.meta["posted_at"]}" <>
        ballot_line(ballot)

    replies =
      Enum.map_join(t.replies, "\n\n", fn
        %{meta: %{"draft" => "changed"}} = r ->
          "--- #{String.trim(r.body)} (#{r.meta["at"]})"

        r ->
          vote = if r.meta["vote"], do: ", votes #{r.meta["vote"]}", else: ""

          answers =
            if r.meta["in_reply_to"], do: ", answering ##{r.meta["in_reply_to"]}", else: ""

          "--- Reply ##{r.meta["reply"]} by #{r.meta["by"]} at #{r.meta["at"]}#{vote}#{answers}#{earlier(r, doc)}:\n#{String.trim(r.body)}"
      end)

    head <>
      "\n\n" <>
      String.trim(t.trunk.body) <>
      doc_text(doc) <>
      if(replies == "", do: "\n\nNo replies yet.", else: "\n\n" <> replies)
  end

  defp doc_text(nil), do: ""

  defp doc_text(%{present: false} = doc),
    do: "\n\n(#{doc.path} is no longer in the house.)"

  defp doc_text(doc),
    do:
      "\n\n=== #{doc.path}, its latest draft#{draft_at(doc.commit)} ===\n#{String.trim(doc.content)}\n=== end of #{doc.path} ==="

  # A reply on an earlier draft than the latest says so (seshat#83).
  defp earlier(%{meta: %{"doc_commit" => c}}, %{commit: latest}) when c != latest,
    do: ", on an earlier draft (#{short(c)})"

  defp earlier(_reply, _doc), do: ""

  defp ballot_line(nil), do: ""

  defp ballot_line(%{closed_at: nil} = b),
    do:
      "\nBallot ##{b.number}, open until #{iso(b.closes_at)}: #{votes_cast(length(b.votes))} so far."

  defp ballot_line(b), do: "\nBallot ##{b.number}, closed #{iso(b.closed_at)}: #{b.outcome}"

  defp votes_cast(1), do: "1 vote cast"

  defp votes_cast(n), do: "#{n} votes cast"

  @doc false
  def next_reply(view, thread) do
    view.files
    |> Repos.under(Path.join(thread, "replies"))
    |> Enum.map(
      &(&1
        |> Path.basename()
        |> String.split("-", parts: 2)
        |> hd()
        |> Integer.parse())
    )
    |> Enum.map(fn
      {n, ""} -> n
      _ -> 0
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  @doc false
  def reply_path(thread, number, name),
    do:
      Path.join([
        thread,
        "replies",
        "#{String.pad_leading(Integer.to_string(number), 4, "0")}-#{slug(name)}.md"
      ])

  @doc false
  # A path in the household's repository: plain segments under a
  # household kind's folder (`Kinds.normalize/1` holds the shape).
  def household_path(name) do
    with {:ok, path} <- Kinds.normalize(to_string(name)) do
      if Enum.any?(Kinds.household(), &(&1.kind == Kinds.kind_of(path).kind)),
        do: {:ok, path},
        else:
          {:error,
           Error.new(:seshat_household_invalid, :seshat_household_kind_not_hosted, path: path)}
    end
  end

  @doc false
  # `threads/<id>`, its trunk's path, a reply's, or the id alone.
  def thread_path(name) when is_binary(name) do
    case String.split(String.trim(name), "/", trim: true) do
      ["threads", id | _] -> if segment?(id), do: "threads/" <> id
      [id] -> if segment?(id) and id not in [@contract, "contract", "beats"], do: "threads/" <> id
      _ -> nil
    end
  end

  def thread_path(_other), do: nil

  defp segment?(s), do: Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,99}\z/, s)

  @doc false
  def no_thread(name),
    do:
      {:error,
       Error.new(:seshat_household_no_such_thread, :seshat_household_thread_absent,
         path: to_string(name)
       )}

  @doc false
  def fresh_id(view, title) do
    base = "#{Date.to_iso8601(DateTime.to_date(Clock.now()))}-#{slug(title)}"

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(&(Repos.under(view.files, "threads/" <> &1) == []))
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, 60)
    |> String.trim("-")
    |> case do
      "" -> "post"
      s -> s
    end
  end

  @doc false
  def render(meta, body) do
    lines = Enum.map_join(meta, "\n", fn {k, v} -> "#{k}: #{one_line(v)}" end)
    "---\n#{lines}\n---\n\n#{String.trim_trailing(body)}\n"
  end

  @doc false
  def frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---\n", parts: 2) do
      [head, body] ->
        meta = head |> String.split("\n", trim: true) |> Enum.flat_map(&meta_line/1) |> Map.new()
        {meta, String.trim_leading(body, "\n")}

      _ ->
        {%{}, rest}
    end
  end

  def frontmatter(text), do: {%{}, text}

  defp meta_line(line) do
    case String.split(line, ": ", parts: 2) do
      [k, v] -> [{k, v}]
      _ -> []
    end
  end

  @doc false
  # One commit under the writer's name (sima-qian#52), every file created
  # where it was absent (seshat#59: written once, so two writers never
  # land on one file) or put where it was as read (sima-qian#57).
  def commit(view, changes, message, by) do
    with {:ok, _} = written <- Repos.write(view.repo, changes, message, by) do
      announce(view.repo, changes)
      written
    end
  end

  # A thread written is announced to its owner's live channel (the house,
  # or the resident whose own threads they are, seshat#108): the thread's
  # path, never its words, so an open page reads it again and never polls.
  defp announce({_kind, owner}, changes) do
    changes
    |> Enum.map(&elem(&1, 1))
    |> Enum.flat_map(fn path ->
      case is_binary(path) && Regex.run(~r{\Athreads/([^/]+)/}, path) do
        [_, id] -> ["threads/" <> id]
        _other -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.each(fn thread ->
      notice = %{kind: "ThreadWritten", stream: "threads", ref: thread, position: Notices.head()}
      PubSub.broadcast(:apsu, :notices, {owner, notice})
    end)
  end

  @doc false
  # The gate and the write it allows are one step (seshat#67): two writes
  # cannot both pass on one count. The repository itself is ordered by
  # its server; this orders the household's rules. Each step reads the
  # house fresh, so a number or a name it picks is the next one. The
  # lock keeps the front's name it had before the split, as an atom: an
  # alias here would be a runtime edge up to the front, the cycle the
  # gate refuses.
  def locked(household_id, fun) do
    :global.trans({{:"Elixir.Oneiroi.Seshat.Household", household_id}, self()}, fn ->
      with {:ok, view} <- view(household_id), do: fun.(view)
    end)
  end

  @doc false
  def titled(nil),
    do: {:error, Error.new(:seshat_household_invalid, :seshat_household_title_missing)}

  def titled(title) do
    if String.length(title) <= @title_max,
      do: :ok,
      else: {:error, Error.new(:seshat_household_invalid, :seshat_household_title_long)}
  end

  @doc false
  def worded(text, optional?) do
    cond do
      String.length(text) > @text_max ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_text_long)}

      String.trim(text) == "" and not optional? ->
        {:error, Error.new(:seshat_household_invalid, :seshat_household_text_missing)}

      true ->
        :ok
    end
  end

  @doc false
  def one_line(nil), do: nil

  def one_line(v),
    do: v |> to_string() |> String.replace(~r/\s*\n\s*/, " ") |> String.trim() |> blank()

  @doc false
  def blank(nil), do: nil

  def blank(v) when is_binary(v), do: if(String.trim(v) == "", do: nil, else: String.trim(v))

  def blank(v), do: to_string(v)

  @doc false
  def integer(n) when is_integer(n) and n > 0, do: n

  def integer(_), do: nil

  @doc false
  def iso(nil), do: nil

  def iso(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  def iso(other), do: to_string(other)
end
