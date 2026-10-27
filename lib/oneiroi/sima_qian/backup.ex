defmodule Oneiroi.SimaQian.Backup do
  @moduledoc """
  The nightly unit (spec §6.10): export, root, commit by class with the
  trailers, push, and record both facts on the resident's stream.

  Commits by class as David's backup does: the soul alone, writing and
  research apart, machine state together; anything else uncommitted fails
  the run after the rest has landed, so a stray write is loud and the
  backup is still taken. In P0 the only class with files is the machine
  one, `records/`; the table is here so the others arrive as rows.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.AgathosDaimon.Store
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.Merkle

  @classes [
    {"soul", ["SOUL.md", "honcho/"]},
    {"writing", ["writing/", "research/"]},
    {"machine",
     ["records/", "memory/", "feeds/", "mail/", "correspondence/", "design/", "wiki/", "journal/"]}
  ]

  def set_remote(resident_id, url, token, %Actor{} = actor) when is_binary(url) do
    ciphertext = (token || "") |> Vault.encrypt() |> Base.encode64()

    command = %Commands.SetRecordsRemote{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      url: url,
      token_ciphertext: ciphertext
    }

    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  def run(resident_id, %Actor{} = actor) do
    dir = dir(resident_id)
    row = Scope.resident(resident_id, fn -> Store.get(resident_id) end)

    with :ok <- Git.ensure_repo(dir),
         {:ok, export} <- Export.write(resident_id, dir),
         {:ok, _} <- record_export(resident_id, export, actor),
         root = Merkle.root(Path.join(dir, "records")),
         {:ok, commits} <- commit_classes(dir, export.through, root),
         :ok <- push(dir, row),
         {:ok, _} <- record_backup(resident_id, export.through, root, commits, actor) do
      :telemetry.execute([:oneiroi, :sima_qian, :backup], %{through: export.through}, %{
        resident_id: resident_id
      })

      case Git.stray(dir, Enum.flat_map(@classes, &elem(&1, 1))) do
        [] -> {:ok, %{through: export.through, root: root, commits: commits}}
        stray -> {:error, Error.new(:sima_qian_stray_files, paths: stray)}
      end
    end
  end

  def attest(resident_id, %Actor{} = actor) do
    dir = dir(resident_id)
    row = Scope.resident(resident_id, fn -> Store.get(resident_id) end)

    cond do
      is_nil(row) or is_nil(row.last_backup_root) ->
        {:ok, :none}

      Merkle.root(Path.join(dir, "records")) == row.last_backup_root ->
        {:ok, :held}

      true ->
        actual = Merkle.root(Path.join(dir, "records"))

        command = %Commands.RecordMismatch{
          actor: actor,
          at: Clock.now(),
          id: resident_id,
          expected_root: row.last_backup_root,
          actual_root: actual,
          commit: row.last_backup_commit
        }

        with {:ok, _} <- Router.dispatch(command), do: {:ok, :mismatch}
    end
  end

  @doc "Every resident with a remote, for the nightly jobs; platform scope by name."
  def residents_with_remote, do: Scope.platform(fn -> Store.with_remote() end)

  @doc "The resident's working repository."
  def dir(resident_id), do: Path.join(Config.fetch!(:sima_qian, :root), resident_id)

  defp record_export(resident_id, export, actor) do
    Router.dispatch(%Commands.RecordExport{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      through: export.through,
      files: export.files
    })
  end

  defp commit_classes(dir, through, root) do
    message = fn class ->
      "Records: #{class} through sequence #{through}\n\nOneiroi-Sequence: #{through}\nOneiroi-Root: #{root}\n"
    end

    Enum.reduce_while(@classes, {:ok, []}, fn {class, paths}, {:ok, acc} ->
      case commit_class(
             dir,
             Enum.filter(paths, &File.exists?(Path.join(dir, &1))),
             message.(class)
           ) do
        {:ok, :nothing} -> {:cont, {:ok, acc}}
        {:ok, sha} -> {:cont, {:ok, acc ++ [{class, sha}]}}
        {:error, reason} -> {:halt, {:error, {:git, reason}}}
      end
    end)
  end

  defp commit_class(_dir, [], _message), do: {:ok, :nothing}
  defp commit_class(dir, present, message), do: Git.commit(dir, present, message)

  defp push(_dir, %{remote_url: nil}), do: :ok
  defp push(_dir, nil), do: :ok

  defp push(dir, %{remote_url: url, remote_token: token}) do
    remote =
      case {token && Vault.decrypt(token), url} do
        {{:ok, ""}, _} -> url
        {{:ok, plain}, "https://github.com/" <> _} -> Git.github_url(url, plain)
        _ -> url
      end

    Git.push(dir, remote)
  end

  defp record_backup(_resident_id, _through, _root, [], _actor), do: {:ok, []}

  defp record_backup(resident_id, through, root, commits, actor) do
    {_class, sha} = List.last(commits)

    Router.dispatch(%Commands.RecordBackup{
      actor: actor,
      at: Clock.now(),
      id: resident_id,
      sequence: through,
      root: root,
      commit: sha
    })
  end
end
