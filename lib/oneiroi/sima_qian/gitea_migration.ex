defmodule Oneiroi.SimaQian.GiteaMigration do
  @moduledoc """
  The one move onto Gitea (sima-qian#58; the witness, 2026-11-16: "we'll
  migrate everything in one go with no weird intermediate states"). At
  boot, with the platform's repositories on Gitea, every working
  repository still on the records disk is sent whole, its history with
  it: each household's (`households/<id>`) and each resident's
  (`<resident id>`). Each one sent is marked in its own `.git`, so a
  restart sends only what is left; once the disk is gone there is
  nothing to send and this does nothing.

  While it runs, every write to Gitea is refused (`migrating?/0`,
  `sima_qian_gitea_unavailable`): a write landing first would make the
  repository and leave the push no history to join. Reads see what has
  arrived so far. A repository that fails to send is logged and left
  unmarked, so the next boot tries again; the writes are opened all the
  same, since the rest of the platform has arrived.
  """

  require Logger

  alias Oneiroi.Config
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Gitea
  alias Oneiroi.SimaQian.GiteaQueue
  alias Oneiroi.SimaQian.Repos

  @marker "oneiroi-sent-to-gitea"

  @doc false
  def child_spec(_arg),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}

  @doc "Starts the move when there is anything to move; `:ignore` when there is not."
  def start_link do
    case pending() do
      [] ->
        :ignore

      repos ->
        GiteaQueue.moving(true)
        Task.start_link(fn -> run(repos) end)
    end
  end

  @doc "Whether the move is under way, so writes wait for it."
  @spec migrating?() :: boolean()
  defdelegate migrating?(), to: GiteaQueue, as: :moving?

  @doc """
  The working repositories not yet sent, as `{kind, id, dir}`; none
  unless the platform's repositories are on Gitea and it is set up.
  """
  def pending do
    if Config.fetch!(:sima_qian, :repos_client) == Repos.Gitea and Gitea.configured?(),
      do: Enum.reject(on_disk(), fn {_kind, _id, dir} -> sent?(dir) end),
      else: []
  end

  @doc "Sends each repository in turn, marking each one sent, then opens the writes."
  def run(repos) do
    Logger.info("gitea: moving #{length(repos)} repositories")

    failed =
      Enum.reject(repos, fn {kind, id, dir} ->
        case move(kind, id) do
          {:ok, _} ->
            mark(dir)

          other ->
            Logger.error("gitea: #{kind} #{id} was not sent: #{inspect(other)}")
            false
        end
      end)

    Logger.info("gitea: moved #{length(repos) - length(failed)} of #{length(repos)}")
    :ok
  after
    GiteaQueue.moving(false)
  end

  # What was on the disk is committed first (sima-qian#62): before #95 a
  # library write reached the disk at once and git only at the nightly
  # backup, and the push sends history, so the first move (2026-11-17)
  # left behind everything written since the night's backup.
  defp move(kind, id) do
    dir = dir_of(kind, id)

    with {:ok, _} <- before_the_move(dir) do
      case kind do
        :household -> Gitea.sync_household(id)
        :resident -> Gitea.sync_resident(id)
      end
    end
  end

  defp before_the_move(dir) do
    if repo?(dir),
      do: Git.commit(dir, ["."], "Before the move: what was on the disk"),
      else: {:ok, :nothing}
  end

  defp dir_of(:household, id), do: Path.join([Config.fetch!(:sima_qian, :root), "households", id])
  defp dir_of(:resident, id), do: Path.join(Config.fetch!(:sima_qian, :root), id)

  @doc """
  Writes into Gitea what the first move left on the disk (sima-qian#62):
  for each repository already sent, every file on the disk that its last
  commit did not carry, new or changed. Nothing is overwritten that was
  written since the move: a file Gitea does not have is created, one
  Gitea still holds as the move sent it is replaced, and one Gitea has
  since changed, or deleted, is left alone and named. One commit per
  repository, the platform's. Run once, from the release:
  `Oneiroi.SimaQian.GiteaMigration.recover()`; it answers what it did.
  """
  def recover do
    for {kind, id, dir} <- on_disk(), sent?(dir) do
      {kind, id, recover_one({kind, id}, dir)}
    end
  end

  defp recover_one(repo, dir) do
    with {:ok, sent} <- sent_tree(dir),
         {:ok, now} <- Repos.snapshot(repo) do
      {changes, left} =
        dir
        |> disk_files()
        |> Enum.reject(fn {path, sha, _bytes} -> Map.get(sent, path) == sha end)
        |> Enum.reduce({[], []}, &sort_out(&1, &2, sent, now))

      with {:ok, commit} <-
             Repos.write(
               repo,
               Enum.reverse(changes),
               "Recovered: written on the disk before the move to Gitea",
               Repos.platform()
             ) do
        %{written: Enum.map(changes, &elem(&1, 1)), left: Enum.reverse(left), commit: commit}
      end
    end
  end

  defp sort_out({path, sha, bytes}, {changes, left}, sent, now) do
    case recovered(path, sha, bytes, Map.get(sent, path), Map.get(now, path)) do
      nil -> {changes, left}
      :left -> {changes, [path | left]}
      change -> {[change | changes], left}
    end
  end

  # The disk's copy (`sha`), what the move sent (`sent`), what Gitea holds now (`now`).
  defp recovered(_path, sha, _bytes, _sent, sha), do: nil
  defp recovered(path, _sha, bytes, nil, nil), do: {:create, path, bytes}

  defp recovered(path, _sha, bytes, sent, sent) when is_binary(sent),
    do: {:put, path, bytes, sent}

  defp recovered(_path, _sha, _bytes, _sent, _now), do: :left

  defp sent_tree(dir) do
    with {:ok, entries} <- Git.tree(dir, "HEAD"),
         do: {:ok, for(%{type: "blob", path: p, blob: b} <- entries, into: %{}, do: {p, b})}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp disk_files(dir) do
    for full <- Path.wildcard(Path.join(dir, "**"), match_dot: true),
        File.regular?(full),
        rel = Path.relative_to(full, dir),
        rel != ".git" and not String.starts_with?(rel, ".git/") do
      bytes = File.read!(full)
      {rel, Repos.Local.sha(bytes), bytes}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp on_disk do
    root = Config.fetch!(:sima_qian, :root)
    households = Path.join(root, "households")

    homes =
      for id <- ls(households),
          uuid?(id),
          repo?(Path.join(households, id)),
          do: {:household, id, Path.join(households, id)}

    residents =
      for id <- ls(root),
          uuid?(id),
          repo?(Path.join(root, id)),
          do: {:resident, id, Path.join(root, id)}

    homes ++ residents
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> Enum.sort(names)
      {:error, _} -> []
    end
  end

  defp uuid?(name), do: match?({:ok, _}, Ecto.UUID.cast(name))

  # sobelow_skip ["Traversal.FileModule"]
  defp repo?(dir), do: File.dir?(Path.join(dir, ".git"))

  # sobelow_skip ["Traversal.FileModule"]
  defp sent?(dir), do: File.exists?(Path.join([dir, ".git", @marker]))

  # sobelow_skip ["Traversal.FileModule"]
  defp mark(dir), do: File.write(Path.join([dir, ".git", @marker]), "") == :ok
end
