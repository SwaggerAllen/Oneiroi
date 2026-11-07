defmodule Oneiroi.Gaia.Boots do
  @moduledoc """
  The platform's boots (gaia#21; the witness, 2026-11-06: any restart is
  said, "otherwise the intersection of memory, model and code isn't
  clear"). At each start the platform records, on its own stream, the
  commit it runs (`RENDER_GIT_COMMIT`), the commit the boot before ran,
  and whether they differ. It says what restarted, never why. The
  conversations read them (brain#63) and the operator lists them.
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.PlatformRouter
  alias Oneiroi.Gaia.Store.Boot
  alias Oneiroi.Repo
  alias Oneiroi.Scope

  @doc "Records this start, when the setting asks it (off in the suite); a failure is logged, never raised."
  def record_now do
    if Config.fetch!(:gaia, :record_boots), do: record(Config.fetch!(:gaia, :commit))
    :ok
  end

  @doc "Records a boot running `commit` (nil when the host gives none)."
  def record(commit) do
    command = %Commands.RecordBoot{
      actor: Actor.platform(),
      at: Clock.now(),
      id: Door.stream(),
      commit: commit
    }

    case PlatformRouter.dispatch(command) do
      {:ok, _events} ->
        :ok

      {:error, reason} ->
        e = Error.caught(:gaia_dispatch_failed, :gaia_boot_not_recorded, reason)
        Logger.warning("gaia: the boot was not recorded", Oneiroi.Error.metadata(e))
        {:error, e}
    end
  end

  @doc "The boots after `at`, oldest first: the restarts a conversation has not been told of."
  @spec since(DateTime.t()) :: [Boot.t()]
  def since(%DateTime{} = at) do
    stream = Door.stream()

    Scope.platform(fn ->
      Repo.all(
        from(b in Boot,
          where: b.stream_key == ^stream and b.booted_at > ^at,
          order_by: b.number
        )
      )
    end)
  end

  @doc "The latest boots, newest first, for the operator."
  @spec latest(pos_integer()) :: [Boot.t()]
  def latest(limit) do
    stream = Door.stream()

    Scope.platform(fn ->
      Repo.all(
        from(b in Boot,
          where: b.stream_key == ^stream,
          order_by: [desc: b.number],
          limit: ^limit
        )
      )
    end)
  end

  @doc "A boot as one line: when, the commits, changed or not, and the diff to read when it changed."
  @spec line(Boot.t(), String.t()) :: String.t()
  def line(%Boot{} = b, stamp) do
    now = short(b.commit)

    cond do
      b.number == 1 or is_nil(b.previous) ->
        "The platform started at #{stamp}, running commit #{now}."

      b.changed ->
        "The platform restarted at #{stamp}: commit #{short(b.previous)} → #{now}, changed. The diff: #{Config.fetch!(:gaia, :source_url)}/compare/#{b.previous}...#{b.commit}"

      true ->
        "The platform restarted at #{stamp}, same commit (#{now})."
    end
  end

  defp short(nil), do: "unknown"
  defp short(commit), do: String.slice(commit, 0, 7)
end
