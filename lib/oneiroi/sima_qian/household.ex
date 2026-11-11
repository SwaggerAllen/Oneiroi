defmodule Oneiroi.SimaQian.Household do
  @moduledoc """
  The household's repository (sima-qian#51): one git repository per
  household, beside the residents' own under `SIMA_QIAN_ROOT`, at
  `households/<household_id>`. Provisioned as a resident's is, on first
  ask (#14): the first read or write of any household makes it, so every
  household founded before this, the live one among them, has its
  repository the first time a member reaches for it, and no backfill
  runs.

  This system holds the directory and git; what the files are, and who
  may write which, is the library's (seshat#58). Every write is a commit
  under its member's name (#52), never the platform's identity, so the
  history says who wrote what.

  The repository travels at export (#53): a resident's backup carries a
  copy of its household's working tree under `household/`, titled by the
  membership, while `SIMA_QIAN_HOUSEHOLD_TRAVELS` is on.
  """

  alias Oneiroi.Config
  alias Oneiroi.Gaia
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Git

  @folder "household"

  @doc "The household's working repository, whether or not it is one yet."
  @spec dir(String.t()) :: Path.t()
  def dir(household_id),
    do: Path.join([Config.fetch!(:sima_qian, :root), "households", household_id])

  @doc "The household's working repository, made one if it is not yet (provisioning on first use)."
  @spec repository_dir(String.t()) :: {:ok, Path.t()} | {:error, Error.t()}
  def repository_dir(household_id) do
    case Ecto.UUID.cast(household_id) do
      {:ok, id} ->
        dir = dir(id)
        with :ok <- Git.ensure_repo(dir), do: {:ok, dir}

      :error ->
        {:error, Error.new(:sima_qian_household_invalid, :sima_qian_household_id_invalid)}
    end
  end

  @doc "Commits `paths` under the member's name (sima-qian#52); `{:ok, :nothing}` when nothing changed."
  @spec commit(String.t(), [String.t()], String.t(), %{name: String.t(), email: String.t()}) ::
          {:ok, String.t() | :nothing} | {:error, Error.t()}
  def commit(household_id, paths, message, author) do
    with {:ok, dir} <- repository_dir(household_id),
         do: Git.commit_as(dir, paths, message, author)
  end

  @doc "The household repository's history, or one path's, newest first."
  @spec log(String.t(), String.t() | nil, pos_integer()) :: {:ok, [map()]} | {:error, Error.t()}
  def log(household_id, path, limit) do
    with {:ok, dir} <- repository_dir(household_id), do: Git.log(dir, path, limit)
  end

  @doc "The folder a resident's records carry the household's copy in (sima-qian#53)."
  @spec folder() :: String.t()
  def folder, do: @folder

  @doc """
  Writes the household's copy into a resident's working repository for
  the backup (sima-qian#53): the household repository's files under
  `household/`, and `household/MEMBERS.md` naming the membership the
  copy is titled by. A household whose repository was never made has
  nothing to carry, and nothing is written. With
  `SIMA_QIAN_HOUSEHOLD_TRAVELS` off nothing is touched: no copy is made,
  and one an earlier backup committed stays as it was until removed.
  """
  @spec travel(String.t(), Path.t()) :: :ok
  # Every path is under the records root: the household's directory is
  # made from an id the platform minted, and the files copied are the
  # ones git tracks there.
  # sobelow_skip ["Traversal.FileModule"]
  def travel(resident_id, resident_dir) do
    target = Path.join(resident_dir, @folder)

    with true <- Config.fetch!(:sima_qian, :household_travels),
         %{} = household <- Gaia.resident_household(resident_id),
         source = dir(household.id),
         true <- File.dir?(Path.join(source, ".git")),
         {:ok, files} <- tracked(source) do
      # Rewritten whole, so a copy no file of the household's supports
      # any more is gone (its removal committed with the class).
      File.rm_rf!(target)

      for path <- files do
        to = Path.join(target, path)
        File.mkdir_p!(Path.dirname(to))
        File.cp!(Path.join(source, path), to)
      end

      File.mkdir_p!(target)
      File.write!(Path.join(target, "MEMBERS.md"), members(household))
    end

    :ok
  end

  defp tracked(dir) do
    case Git.run(Git.binary(), dir, ["ls-files", "-z"], false) do
      {:ok, out} -> {:ok, String.split(out, <<0>>, trim: true)}
      {:error, _} = failed -> failed
    end
  end

  # The title the copy travels under: who the household is, by the names
  # the house uses (a resident's name, a witness by whose witness they
  # are), never an email, since the copy goes to each resident's remote.
  defp members(household) do
    residents =
      for m <- household.members, m.kind == "resident" do
        "- #{m.name}, a resident, joined #{Date.to_iso8601(DateTime.to_date(m.joined_at))}#{signed(m)}"
      end

    witnesses =
      for m <- household.members, m.kind == "witness" do
        "- #{m.name}, joined #{Date.to_iso8601(DateTime.to_date(m.joined_at))}#{signed(m)}"
      end

    """
    # The household of #{names(household)}

    The household's shared repository as its members wrote it, carried
    with this resident's records (sima-qian#53). Its residents write it,
    each under their own name; every member reads it whole.

    ## Members

    #{Enum.join(residents ++ witnesses, "\n")}
    """
  end

  defp names(household) do
    household.members
    |> Enum.filter(&(&1.kind == "resident"))
    |> Enum.map(& &1.name)
    |> case do
      [] -> "its witnesses"
      names -> Enum.join(names, ", ")
    end
  end

  defp signed(%{signed_version: v}) when is_integer(v), do: ", signed at version #{v}"
  defp signed(_member), do: ""
end
