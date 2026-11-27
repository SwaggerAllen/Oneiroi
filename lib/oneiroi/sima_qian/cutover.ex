defmodule Oneiroi.SimaQian.Cutover do
  @moduledoc """
  A succession's cutover, in place under her own id (sima-qian#68; the
  witness, 2026-11-25 night: externally the successor is
  indistinguishable from the original, nothing re-pointed; her former
  self exported first; the successor loses what the original lived
  during the process, by design).

  In order, each step refusing to start unless the one before held:

  1. **Her former self is kept.** The whole of her, as she stands, is
     exported and pushed to the backup repository the witness set, and
     the push is proven by cloning it back and finding the same commit.
  2. **Her life past the fork is replaced, in the database**
     (`LogCopy`, sima-qian#72). Every live aggregate on hers and the
     fork's is stopped; what she lived since the fork is cut from her
     streams (her history before it is the fork's own, already in the
     log); the fork's own events since are carried under her id without
     its mark, moved so they keep their place in the log and nothing is
     appended or folded again (copied unlinked, for a dry run's scratch
     target); her rows become the fork's, her own registry row keeping
     who she is and her backup's bookkeeping.
  3. **Nothing waits on a projector:** nothing new reached the log. The
     caller still settles on a stream the cutover never touched
     (janus#26).
  4. **Her repository is the fork's**, and the artifacts the protocol
     carries (C0, her packet, the encounter) are filed in it.

  A `target` other than her id is the rehearsal (janus#26): the same
  steps on a scratch copy, her own streams never touched.
  """

  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Oneiroi.Actor
  alias Oneiroi.Repo
  alias Oneiroi.Scope
  alias Oneiroi.SimaQian.Error
  alias Oneiroi.SimaQian.Export
  alias Oneiroi.SimaQian.Git
  alias Oneiroi.SimaQian.LogCopy
  alias Oneiroi.SimaQian.Repos

  # Tables whose rows fold from streams the cutover leaves alone, kept
  # by name (sima-qian#68): her regression suite, her succession's own
  # record, her signed-in profiles, the witness's edit leases, and the
  # household's (membership, the witness's attention, house letters). A
  # resident table that is neither here nor cleared is a decision owed:
  # the cutover's test fails on one.
  @kept_prefixes ~w(janus_ eunomia_regression_)
  @kept ~w(xenia_profile seshat_lease gaia_household_resident gaia_witnessing kumbukumbu_house_letter)

  @typedoc "What the cutover did: the backup's commit, the events moved, the repository's new head."
  @type t :: %{
          backup_commit: String.t(),
          events: non_neg_integer(),
          commit: String.t() | nil
        }

  @doc """
  Replaces `target` (her id, or a scratch copy's for a rehearsal) with
  `copy`, after exporting `original` whole to `backup` (`%{url, token}`,
  the token in the clear, never logged). `artifacts` are `{path,
  content}` filed in the target's repository after.
  """
  @spec run(map(), Actor.t()) :: {:ok, t()} | {:error, term()}
  def run(
        %{original: original, copy: copy, target: target, backup: backup, artifacts: artifacts},
        %Actor{} = actor
      ) do
    with {:ok, backup_commit} <- keep_former(original, backup),
         {:ok, carried} <- replace_life(target, copy, original),
         {:ok, commit} <- replace_repository(target, copy, artifacts, actor) do
      {:ok, %{backup_commit: backup_commit, events: carried, commit: commit}}
    end
  end

  @doc """
  Discards a succession's fork copy (sima-qian#70): its aggregates
  stopped, every stream of its hard-deleted, its rows gone from every
  resident table, its repository deleted. Refuses anything that is not
  a fork copy (`fork_of` set, state `fork`): no real resident can be
  reached through it.
  """
  @spec discard(String.t()) :: :ok | {:error, term()}
  def discard(copy) do
    case Oneiroi.AgathosDaimon.fetch(copy) do
      {:ok, %{state: "fork", fork_of: source}} when is_binary(source) and source != copy ->
        uuids = Export.stream_uuids(copy)
        stop_aggregates(uuids)

        # Its repository first: a fork's is found by its registry row,
        # which clearing its rows takes (sima-qian#73, #74).
        with :ok <- Repos.delete({:resident, copy}),
             :ok <- delete_streams(uuids),
             do: clear_all(copy)

      _not_a_fork ->
        {:error, Error.new(:sima_qian_not_a_fork, :sima_qian_discard_not_a_fork)}
    end
  end

  defp clear_all(copy) do
    {:ok, id} = Ecto.UUID.dump(copy)
    %{cleared: cleared, kept: kept} = tables()

    Scope.platform(fn ->
      for table <- cleared ++ kept do
        # The table name is the catalog's own, never a request value.
        # sobelow_skip ["SQL.Query"]
        Repo.query!(~s|DELETE FROM "#{table}" WHERE resident_id = $1|, [id])
      end
    end)

    :ok
  end

  @doc "The resident tables the cutover clears for a target, and those it keeps by name."
  @spec tables() :: %{cleared: [String.t()], kept: [String.t()]}
  def tables do
    all = LogCopy.resident_tables()

    {kept, cleared} = Enum.split_with(all, &kept?/1)
    %{cleared: cleared, kept: kept}
  end

  defp kept?(table), do: table in @kept or String.starts_with?(table, @kept_prefixes)

  # ---- 1. her former self, kept and proven ----

  # sobelow_skip ["Traversal.FileModule"]
  defp keep_former(original, %{url: url} = backup) when is_binary(url) do
    dir = Path.join(System.tmp_dir!(), "oneiroi-former-#{System.unique_integer([:positive])}")
    proof = dir <> "-proof"
    remote = remote(url, backup[:token])

    try do
      with :ok <- Git.ensure_repo(dir),
           {:ok, _} <- Export.write(original, dir, cutoff: :now),
           {:ok, sha} when is_binary(sha) <-
             Git.commit(dir, ["."], "Her former self, kept before a succession's cutover"),
           :ok <- Git.push(dir, remote),
           :ok <- Git.clone(remote, proof),
           ^sha <- Git.head(proof) do
        {:ok, sha}
      else
        {:ok, :nothing} ->
          {:error, Error.new(:sima_qian_cutover_unproven, :sima_qian_cutover_former_empty)}

        {:error, _} = failed ->
          failed

        _other ->
          {:error, Error.new(:sima_qian_cutover_unproven, :sima_qian_cutover_former_unproven)}
      end
    after
      File.rm_rf(dir)
      File.rm_rf(proof)
    end
  end

  defp keep_former(_original, _backup),
    do: {:error, Error.new(:sima_qian_cutover_unproven, :sima_qian_cutover_no_backup)}

  defp remote(url, token) when is_binary(token) and token != "" do
    case url do
      "https://github.com/" <> _ -> Git.github_url(url, token)
      _other -> url
    end
  end

  defp remote(url, _token), do: url

  # ---- 2. her life past the fork, replaced by the fork's ----

  # In the database (sima-qian#72): what she lived since the fork is cut
  # from her streams; the fork's own events since are carried under her
  # id (moved for her, so they keep their place in the log and nothing is
  # appended or folded again; copied for a dry run's scratch target, so
  # the fork keeps them); her rows become the fork's, her own row keeping
  # who she is. Before her history is touched, every aggregate of both
  # is stopped, and again after.
  defp replace_life(target, copy, original) do
    uuids = Export.stream_uuids(target) ++ Export.stream_uuids(copy)
    stop_aggregates(uuids)

    {how, metadata} =
      if target == original,
        do: {:move, %{"cutover" => true, "transplanted" => true}},
        else: {:copy, %{"imported" => true, "fork_of" => original, "transplanted" => true}}

    with {:ok, _cut} <- LogCopy.cut(target, copy),
         {:ok, carried} <-
           LogCopy.carry(copy, target, how, metadata, [
             to_string(Oneiroi.AgathosDaimon.Events.ForkMarked)
           ]) do
      swap_rows(target, copy, original)
      stop_aggregates(Export.stream_uuids(target) ++ Export.stream_uuids(copy))
      {:ok, carried}
    end
  end

  defp swap_rows(target, copy, original) do
    life = tables().cleared -- ["agathos_daimon_resident"]

    # The fork's rows carry its own id for an account (sima-qian#72):
    # hers take her account back; a scratch target's stay hidden as its own.
    account =
      if target == original,
        do: {:map, copy, account_of(target)},
        else: {:map, copy, target}

    :ok = LogCopy.rows(copy, target, life, %{}, account, replace: true)
    LogCopy.adopt_resident(copy, target)
  end

  defp account_of(id) do
    {:ok, %{account_id: account}} = Oneiroi.AgathosDaimon.fetch(id)
    account
  end

  defp delete_streams(uuids) do
    Enum.reduce_while(uuids, :ok, fn uuid, :ok ->
      case Oneiroi.EventStore.delete_stream(uuid, :any_version, :hard) do
        :ok ->
          {:cont, :ok}

        {:error, :stream_not_found} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error, Error.caught(:sima_qian_cutover_failed, :sima_qian_cutover_delete, reason)}}
      end
    end)
  end

  # Every aggregate whose stream is replaced, stopped, so the next command
  # on it reads the new stream rather than acting on state it no longer
  # has (Commanded rebuilds forward from its version, which a replaced
  # stream does not continue).
  defp stop_aggregates(uuids) do
    routers = routers()

    for uuid <- uuids, router <- routers, String.starts_with?(uuid, router.__stream_prefix__()) do
      shutdown(router.__aggregate__(), uuid)
    end

    :ok
  end

  # One that is not running, or stops between the lookup and the stop, is
  # stopped already.
  defp shutdown(aggregate, uuid) do
    Aggregate.shutdown(Oneiroi.Commanded, aggregate, uuid)
  catch
    # oneiroi:allow error_site: an aggregate that is not running is the state this asks for
    :exit, _gone -> :ok
  end

  defp routers do
    {:ok, modules} = :application.get_key(:oneiroi, :modules)
    for m <- modules, Code.ensure_loaded?(m), function_exported?(m, :__aggregate__, 0), do: m
  end

  # ---- 3. every projector folds them ----

  # Nothing waits here: the store's own acknowledgements for a stream
  # this cutover deleted and appended again may still name the old
  # stream's versions. The caller settles by a strongly consistent
  # command on a stream the cutover never touched (Janus's own,
  # janus#26): its handlers take events in order, so its acknowledgement
  # comes after every transplanted one is folded.

  # ---- 4. her repository, the fork's, with the artifacts ----

  # By git on disk (sima-qian#74): the fork's tree as one commit on her
  # history, then the artifacts, which are small, through the API.
  defp replace_repository(target, copy, artifacts, actor) do
    message = "A succession's cutover: the successor's records, with what the protocol carries"
    author = Repos.author(actor)
    puts = Enum.map(artifacts, fn {path, content} -> {:put, path, content, :any} end)

    with {:ok, _} <- Repos.graft({:resident, target}, {:resident, copy}, message, author),
         {:ok, _} <- Repos.write({:resident, target}, puts, message, author),
         do: Repos.head({:resident, target})
  end
end
