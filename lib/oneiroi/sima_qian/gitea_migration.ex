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

  defp move(:household, id), do: Gitea.sync_household(id)
  defp move(:resident, id), do: Gitea.sync_resident(id)

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
