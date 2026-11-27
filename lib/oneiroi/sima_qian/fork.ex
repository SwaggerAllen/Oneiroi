defmodule Oneiroi.SimaQian.Fork do
  @moduledoc """
  A succession's fork (sima-qian#67, janus#4): a hidden copy of the
  resident as she stands when the succession opens, made by the same
  replay an import is, so every screening run, her baseline and the
  eventual successor run on a resident the original's later life never
  touches (succession delta §5: the successor starts at the fork).

  The copy is made in the database (`LogCopy`, sima-qian#72): her
  events as the store holds them, to this instant, re-keyed under a new
  id with `fork_of` on every line and written to the copy's own streams
  unlinked from `$all`, so no subscription reads one; then her rows,
  copied table by table, the registry's row a fork from the start
  (agathos-daimon#63: its slug suffixed, its state `fork`, no backup
  remote); then her repository's files at its head, copied byte for byte
  into the copy's repository in one commit; then `MarkFork`, the
  decision on the copy's own stream naming the source, the last of her
  events it holds and the commit it copied.

  Never an import: no `Imported`, no custody move. The copy keeps the
  witness her history names and appears in no list of his.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon.Commands
  alias Oneiroi.AgathosDaimon.Router
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.SimaQian.Cutover
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.LogCopy
  alias Oneiroi.SimaQian.Repos

  @typedoc "The copy: its id, the last of the source's resident events it holds, the commit copied, the lines replayed."
  @type t :: %{
          copy_id: String.t(),
          sequence: non_neg_integer(),
          commit: String.t() | nil,
          events: non_neg_integer()
        }

  @doc "Makes the fork copy of `resident_id`; `{:ok, t()}` or the first step's refusal."
  @spec make(String.t(), Actor.t()) :: {:ok, t()} | {:error, term()}
  def make(resident_id, %Actor{} = actor), do: make_as(resident_id, Ecto.UUID.generate(), actor)

  defp make_as(resident_id, copy_id, actor) do
    case build(resident_id, copy_id, actor) do
      {:ok, _} = made ->
        made

      failed ->
        # Half a copy is never left behind (sima-qian#72): its events, rows
        # and repository go, so the next attempt starts clean.
        _ = LogCopy.remove(copy_id)
        failed
    end
  rescue
    exception ->
      _ = LogCopy.remove(copy_id)
      reraise exception, __STACKTRACE__
  end

  defp build(resident_id, copy_id, actor) do
    with {:ok, slug} <- slug_of(resident_id),
         {:ok, %{events: events, sequence: sequence}} <-
           LogCopy.events(resident_id, copy_id, %{
             "imported" => true,
             "fork_of" => resident_id,
             "transplanted" => true
           }),
         :ok <-
           LogCopy.rows(
             resident_id,
             copy_id,
             Cutover.tables().cleared,
             fork_row(slug, copy_id, resident_id),
             {:all, copy_id}
           ),
         {:ok, commit} <- copy_repository(resident_id, copy_id),
         {:ok, _} <- mark(copy_id, resident_id, sequence, commit, actor) do
      {:ok, %{copy_id: copy_id, sequence: sequence, commit: commit, events: events}}
    end
  end

  defp slug_of(resident_id) do
    case Oneiroi.AgathosDaimon.fetch(resident_id) do
      {:ok, %{slug: slug}} ->
        {:ok, slug}

      :error ->
        {:error, Error.new(:sima_qian_copy_failed, :sima_qian_fork_no_resident)}
    end
  end

  # The registry's row of a fork from the start (agathos-daimon#63): its
  # slug suffixed as a replayed resident's is, and nothing of her backup.
  defp fork_row(slug, copy_id, source),
    do:
      Map.merge(
        %{
          "id" => :to,
          "resident_id" => :to,
          "slug" => slug <> "-" <> String.slice(copy_id, 0, 8),
          "state" => "fork",
          "fork_of" => source
        },
        Map.merge(
          Map.new(
            ~w(remote_url remote_token remote_visibility remote_push remote_checked_at
               last_backup_root last_backup_commit last_backup_at),
            &{&1, nil}
          ),
          %{"exported_through" => 0, "last_backup_sequence" => nil}
        )
      )

  # Her repository at one commit, so a write landing meanwhile cannot
  # tear the copy; the copy's own repository is new, so every path is
  # put whatever stands there (`:any`): the replay's own writers may
  # have rendered a file first.
  defp copy_repository(resident_id, copy_id) do
    source = {:resident, resident_id}

    with {:ok, commit} when is_binary(commit) <- Repos.head(source),
         {:ok, snapshot} <- Repos.snapshot_at(source, commit) do
      changes =
        for path <- snapshot |> Map.keys() |> Enum.sort(),
            bytes = Repos.at(source, snapshot, path),
            is_binary(bytes),
            do: {:put, path, bytes, :any}

      message = "Forked from #{resident_id} at #{commit} for a succession"

      with {:ok, _} <- Repos.write({:resident, copy_id}, changes, message, Repos.platform()),
           do: {:ok, commit}
    else
      # No repository yet: nothing to copy, and the copy names no commit.
      {:ok, nil} -> {:ok, nil}
      other -> other
    end
  end

  defp mark(copy_id, source, sequence, commit, actor) do
    Router.dispatch_sited(%Commands.MarkFork{
      actor: actor,
      at: Clock.now(),
      id: copy_id,
      source: source,
      sequence: sequence,
      commit: commit,
      note: "the fork of #{source} a succession runs on, at its event #{sequence}"
    })
  end
end
