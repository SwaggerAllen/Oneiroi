defmodule Oneiroi.SimaQian.Repos.Gitea do
  @moduledoc """
  The repositories' port on Gitea's API (sima-qian#57), the source of
  truth: a household's repository is `<org>/house`, a resident's is
  `<org>/<slug>` under her household's organization (sima-qian#55). A
  read is one file's contents; a write is one call to Gitea's
  change-files endpoint, one commit, each file held to its condition
  there (a create refused when the path exists, an update refused when
  its sha moved), so Gitea, not this node, orders every write. A
  refusal for a moved file is `sima_qian_repos_conflict`; Gitea not answering
  is `sima_qian_gitea_unavailable`, and the write is refused (the
  witness, 2026-11-16). A repository missing on its first write is made
  (its organization, its readers) and the write tried once more.
  """
  @behaviour Oneiroi.SimaQian.Repos.Adapter

  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.GiteaQueue

  @branch "main"
  @tree_page 1000

  @impl true
  def read(repo, path) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case get(inst, "/repos/#{org}/#{name}/contents/#{enc(path)}", ref: @branch) do
        {:ok, 200, %{"type" => "file", "content" => b64, "sha" => sha}} ->
          {:ok, Base.decode64!(b64, ignore: :whitespace), sha}

        {:ok, status, _} when status in [404, 409] ->
          {:error,
           Error.new(:sima_qian_repos_absent, :sima_qian_repos_gitea_read_absent, path: path)}

        # A listing, not a file: a folder by that name, or a repository
        # Gitea still counts as empty just after a push into it
        # (sima-qian#62), which lists nothing for every path. Either way,
        # no file there.
        {:ok, 200, listing} when is_list(listing) ->
          {:error,
           Error.new(:sima_qian_repos_absent, :sima_qian_repos_gitea_read_listing, path: path)}

        other ->
          failed(other)
      end
    end
  end

  @impl true
  def tree(repo) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo),
         do: tree_pages(inst, org, name, @branch, 1, [])
  end

  @impl true
  def tree_at(repo, commit) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case tree_pages(inst, org, name, commit, 1, []) do
        # Gitea answers an unknown commit 400, a missing repository 404;
        # the tree of a commit that exists is never empty of its commit.
        {:ok, []} -> absent_commit(commit)
        {:error, %{kind: :sima_qian_gitea_failed}} -> absent_commit(commit)
        other -> other
      end
    end
  end

  defp absent_commit(commit),
    do:
      {:error,
       Error.new(:sima_qian_repos_absent, :sima_qian_repos_gitea_commit_absent, commit: commit)}

  @impl true
  def delete(repo) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case request(inst, :delete, "/repos/#{org}/#{name}", nil, []) do
        {:ok, status, _} when status in [204, 404] -> :ok
        other -> failed(other)
      end
    end
  end

  @impl true
  def head(repo) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case get(inst, "/repos/#{org}/#{name}/branches/#{@branch}", []) do
        {:ok, 200, %{"commit" => %{"id" => id}}} -> {:ok, id}
        # No commit yet, or no repository yet: nothing to pin.
        {:ok, 404, _} -> {:ok, nil}
        other -> failed(other)
      end
    end
  end

  # Gitea pages a recursive tree and says `truncated: true` on its last
  # real page too, then answers the page after with `"tree": null`
  # (measured 2026-11-17 on 1.22.6: 1,500 entries, pages of 1,000, 500,
  # then null). That null crashed every listing of a repository past one
  # page, the resident's own among them (sima-qian#63). A page with no
  # entries, or `total_count` reached, ends the walk.
  defp tree_pages(inst, org, name, ref, page, acc, seen \\ 0) do
    case get(inst, "/repos/#{org}/#{name}/git/trees/#{ref}",
           recursive: true,
           per_page: @tree_page,
           page: page
         ) do
      {:ok, 200, %{} = body} ->
        entries = body["tree"] || []

        files =
          for %{"type" => "blob", "path" => p, "sha" => s} <- entries, do: %{path: p, sha: s}

        acc = acc ++ files
        seen = seen + length(entries)

        if more?(body, entries, seen),
          do: tree_pages(inst, org, name, ref, page + 1, acc, seen),
          else: {:ok, acc}

      # An empty repository, or one not made yet: no files.
      {:ok, status, _} when status in [404, 409] ->
        {:ok, acc}

      other ->
        failed(other)
    end
  end

  defp more?(_body, [], _seen), do: false

  defp more?(body, _entries, seen) do
    body["truncated"] == true and
      not (is_integer(body["total_count"]) and seen >= body["total_count"])
  end

  @impl true
  # On disk, never through the contents API (sima-qian#74): the fork's
  # repository made in its place, then her history pushed into it.
  def copy(from, to) do
    with :ok <- moved(),
         :ok <- Gitea.ensure(to),
         {:ok, source} <- remote(from),
         {:ok, target} <- remote(to),
         do: Git.mirror(source, target)
  end

  @impl true
  def graft(target, source, message, author) do
    with :ok <- moved(),
         {:ok, into} <- remote(target),
         {:ok, from} <- remote(source),
         do: Git.graft(into, from, message, author)
  end

  defp remote(repo), do: Gitea.remote(repo)

  @impl true
  def write(repo, changes, message, author) do
    with :ok <- moved(),
         {:ok, {inst, org, name}} <- Gitea.locate(repo),
         {:ok, files} <- files(repo, changes) do
      body = %{
        branch: @branch,
        message: message,
        author: author,
        committer: author,
        files: files
      }

      case committed(post(inst, "/repos/#{org}/#{name}/contents", body)) do
        # Not made yet: made, then the write once more.
        :missing -> again(repo, inst, org, name, body)
        result -> result
      end
    end
  end

  # While the records disk is still being sent (sima-qian#58), no write:
  # one landing first would leave the push no history to join.
  defp moved do
    if GiteaQueue.moving?(),
      do: {:error, Error.new(:sima_qian_gitea_unavailable, :sima_qian_repos_gitea_moving)},
      else: :ok
  end

  defp again(repo, inst, org, name, body) do
    with :ok <- Gitea.ensure(repo) do
      case committed(post(inst, "/repos/#{org}/#{name}/contents", body)) do
        :missing -> failed(:missing)
        result -> result
      end
    end
  end

  defp committed({:ok, 201, %{"commit" => %{"sha" => sha}}}), do: {:ok, sha}
  defp committed({:ok, 404, _}), do: :missing

  defp committed({:ok, 422, %{"message" => why}} = refused),
    do:
      if(conflict?(why),
        do:
          {:error, Error.new(:sima_qian_repos_conflict, :sima_qian_repos_gitea_refused_condition)},
        else: failed(refused)
      )

  defp committed(other), do: failed(other)

  # Gitea's words for a condition that no longer holds.
  defp conflict?(why),
    do: why =~ "already exists" or why =~ "sha does not match" or why =~ "does not exist"

  # Each change as Gitea takes it. `:any` reads the path's sha now, so the
  # write is an update when there is a file and a create when there is not.
  defp files(repo, changes) do
    Enum.reduce_while(changes, {:ok, []}, fn change, {:ok, acc} ->
      case file(repo, change) do
        {:ok, f} -> {:cont, {:ok, acc ++ [f]}}
        other -> {:halt, other}
      end
    end)
  end

  defp file(_repo, {:create, path, content}),
    do: {:ok, %{operation: "create", path: path, content: b64(content)}}

  defp file(_repo, {:put, path, content, nil}),
    do: {:ok, %{operation: "create", path: path, content: b64(content)}}

  defp file(repo, {:put, path, content, :any}) do
    case read(repo, path) do
      {:ok, _, sha} ->
        {:ok, %{operation: "update", path: path, content: b64(content), sha: sha}}

      {:error, %{kind: :sima_qian_repos_absent}} ->
        {:ok, %{operation: "create", path: path, content: b64(content)}}

      other ->
        other
    end
  end

  defp file(_repo, {:put, path, content, sha}),
    do: {:ok, %{operation: "update", path: path, content: b64(content), sha: sha}}

  defp file(repo, {:delete, path, :any}) do
    case read(repo, path) do
      {:ok, _, sha} ->
        {:ok, %{operation: "delete", path: path, sha: sha}}

      {:error, %{kind: :sima_qian_repos_absent}} ->
        {:error,
         Error.new(:sima_qian_repos_conflict, :sima_qian_repos_gitea_delete_absent, path: path)}

      other ->
        other
    end
  end

  defp file(_repo, {:delete, path, sha}), do: {:ok, %{operation: "delete", path: path, sha: sha}}

  @impl true
  def log(repo, path, limit) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case get(inst, "/repos/#{org}/#{name}/commits", commits_query(path, limit)) do
        {:ok, 200, commits} when is_list(commits) ->
          {:ok,
           for c <- commits do
             %{
               sha: String.slice(c["sha"], 0, 7),
               at: get_in(c, ["commit", "author", "date"]),
               author: get_in(c, ["commit", "author", "name"]),
               subject: subject(c)
             }
           end}

        {:ok, status, _} when status in [404, 409] ->
          {:ok, []}

        other ->
          failed(other)
      end
    end
  end

  @impl true
  def history(repo, path, limit) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case get(inst, "/repos/#{org}/#{name}/commits", commits_query(path, limit)) do
        {:ok, 200, commits} when is_list(commits) ->
          {:ok,
           for c <- commits do
             %{
               commit: c["sha"],
               at: get_in(c, ["commit", "author", "date"]),
               subject: subject(c),
               blob: blob_at(inst, org, name, path, c["sha"])
             }
           end}

        {:ok, status, _} when status in [404, 409] ->
          {:ok, []}

        other ->
          failed(other)
      end
    end
  end

  defp blob_at(inst, org, name, path, commit) do
    case get(inst, "/repos/#{org}/#{name}/contents/#{enc(path)}", ref: commit) do
      {:ok, 200, %{"sha" => sha}} -> sha
      _removed -> nil
    end
  end

  @impl true
  def blob(repo, sha) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo) do
      case get(inst, "/repos/#{org}/#{name}/git/blobs/#{sha}", []) do
        {:ok, 200, %{"content" => b64}} -> {:ok, Base.decode64!(b64, ignore: :whitespace)}
        other -> failed(other)
      end
    end
  end

  @doc """
  Her own remote as Gitea's push mirror (sima-qian#16, #57): Gitea pushes
  every commit there itself. Made when missing, remade when the address
  changed; the token is the remote's password and never logged.
  """
  def mirror(repo, url, token) do
    with {:ok, {inst, org, name}} <- Gitea.locate(repo),
         {:ok, 200, mirrors} when is_list(mirrors) <-
           get(inst, "/repos/#{org}/#{name}/push_mirrors", []) do
      if Enum.any?(mirrors, &(&1["remote_address"] == url)),
        do: :ok,
        else: remirror(inst, org, name, mirrors, url, token)
    else
      other -> failed(other)
    end
  end

  defp remirror(inst, org, name, mirrors, url, token) do
    for m <- mirrors,
        do:
          request(
            inst,
            :delete,
            "/repos/#{org}/#{name}/push_mirrors/#{m["remote_name"]}",
            nil,
            []
          )

    body =
      %{remote_address: url, interval: "8h0m0s", sync_on_commit: true}
      |> then(
        &if(token,
          do: Map.merge(&1, %{remote_username: "oauth2", remote_password: token}),
          else: &1
        )
      )

    case post(inst, "/repos/#{org}/#{name}/push_mirrors", body) do
      {:ok, status, _} when status in 200..201 -> :ok
      other -> failed(other)
    end
  end

  defp commits_query(nil, limit), do: [sha: @branch, limit: limit, stat: false, files: false]

  defp commits_query(path, limit),
    do: [sha: @branch, path: path, limit: limit, stat: false, files: false]

  defp subject(c),
    do: c |> get_in(["commit", "message"]) |> to_string() |> String.split("\n") |> hd()

  defp b64(content), do: content |> IO.iodata_to_binary() |> Base.encode64()

  defp enc(path),
    do:
      path
      |> String.split("/")
      |> Enum.map_join("/", fn seg -> URI.encode(seg, &URI.char_unreserved?/1) end)

  defp failed({:error, _} = e), do: e

  defp failed(other),
    do:
      {:error,
       Error.new(:sima_qian_gitea_failed, :sima_qian_repos_refused,
         reason: inspect(other, limit: 5)
       )}

  defp get(inst, path, query), do: request(inst, :get, path, nil, query)
  defp post(inst, path, body), do: request(inst, :post, path, body, [])

  # To the instance the repository's household is routed to (sima-qian#60).
  defp request(inst, method, path, body, query) do
    with {:ok, %{url: url, token: token}} <- GiteaQueue.endpoint(inst) do
      send_request(url, token, method, path, body, query)
    end
  end

  defp send_request(url, token, method, path, body, query) do
    # A repository server, not a model provider: the repositories' port
    # (sima-qian#57), registered in the externals with its local adapter.
    # oneiroi:allow model_port
    case Req.request(
           method: method,
           url: url <> "/api/v1" <> path,
           params: query,
           json: body,
           headers: [{"authorization", "token " <> (token || "")}],
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, status, body}

      {:error, exception} ->
        {:error,
         Error.caught(:sima_qian_gitea_unavailable, :sima_qian_repos_transport, exception)}
    end
  end
end
