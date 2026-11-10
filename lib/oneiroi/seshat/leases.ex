defmodule Oneiroi.Seshat.Leases do
  @moduledoc """
  The witness's edit leases (seshat#55, design/ui-server-work.md S4).

  His editor acquires a lease on a library path, renews it while he
  writes (each renewal may carry his unsaved draft, and a write of his to
  the path renews it too) and releases it when he is done. A lease is
  never revoked: after `SESHAT_LEASE_IDLE_SECONDS` without a renewal it
  becomes takeable, and it is taken only when the resident is waiting on
  that file.

  The wait is her `document_write`: on a path he holds, her write records
  a wait on the lease instead of failing, writes nothing, and tells her
  so, with when the lease becomes takeable. A write of hers on a lease
  already takeable is a wait that takes it at once: his draft, when he
  left one that is not the file's words, is kept first as a document of
  his (`human/drafts/...`, the only place the library keeps the
  witness's words beside hers, seshat#33), the lease is marked taken with
  where the draft went, and her write goes in. She is never handed a
  write that proceeds later: when the lease is released or becomes
  takeable she writes again (the tool's answer says when). One write
  path, and her words stay in her turn, never parked in this table.

  Leases are a plain table, not events: coordination state measured in
  minutes, whose outcomes are recorded where they land (her write and
  his kept draft are each a `DocumentWritten`). Replaying one would lock
  a rebuilt resident's file for an editor nobody has open. The table is
  on spec §6.10's `oneiroi:db-only` list as `leases`.
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Config
  alias Oneiroi.Scope
  alias Oneiroi.Seshat.Documents
  alias Oneiroi.Seshat.Error
  alias Oneiroi.Seshat.Kinds
  alias Oneiroi.Seshat.Store
  alias Oneiroi.Seshat.Store.Lease
  alias Oneiroi.SimaQian

  @doc "Acquires the lease on a path for the witness, or renews his own; refused while another account holds it."
  def acquire(resident_id, path, %Actor{kind: :witness, id: holder}) do
    with {:ok, path} <- Kinds.normalize(resident_id, path),
         do:
           Scope.resident(resident_id, fn ->
             acquired(Store.lease(path), resident_id, path, holder)
           end)
  end

  def acquire(_resident_id, _path, %Actor{}),
    do: {:error, Error.new(:seshat_lease_invalid, :seshat_leases_acquire_witness_only)}

  defp acquired(%Lease{state: "held", holder_id: holder} = lease, _resident_id, _path, holder) do
    now = Clock.now()
    {:ok, view(Store.put_lease(%{lease | renewed_at: now}), now)}
  end

  defp acquired(%Lease{state: "held"} = lease, _resident_id, path, _holder),
    do:
      {:error,
       Error.new(:seshat_lease_held, :seshat_leases_acquire_held,
         path: path,
         holder_id: lease.holder_id,
         renewed_at: lease.renewed_at
       )}

  defp acquired(_none_or_taken, resident_id, path, holder) do
    now = Clock.now()

    lease = %Lease{
      resident_id: resident_id,
      path: path,
      holder_id: holder,
      state: "held",
      acquired_at: now,
      renewed_at: now
    }

    {:ok, view(Store.put_lease(lease), now)}
  end

  @doc "Renews the holder's lease, keeping `draft` (his unsaved words) when one is given; a taken lease says where his draft went."
  def renew(resident_id, path, draft, %Actor{kind: :witness, id: holder}) do
    with {:ok, path} <- Kinds.normalize(resident_id, path),
         do:
           Scope.resident(resident_id, fn -> renewed(Store.lease(path), path, draft, holder) end)
  end

  def renew(_resident_id, _path, _draft, %Actor{}),
    do: {:error, Error.new(:seshat_lease_invalid, :seshat_leases_renew_witness_only)}

  defp renewed(%Lease{state: "held", holder_id: holder} = lease, _path, draft, holder) do
    now = Clock.now()
    draft = if is_binary(draft), do: draft, else: lease.draft
    {:ok, view(Store.put_lease(%{lease | renewed_at: now, draft: draft}), now)}
  end

  defp renewed(%Lease{state: "taken", holder_id: holder} = lease, path, _draft, holder),
    do:
      {:error,
       Error.new(:seshat_lease_taken, :seshat_leases_renew_taken,
         path: path,
         taken_at: lease.taken_at,
         kept_at: lease.kept_at
       )}

  defp renewed(_none_or_another, path, _draft, _holder),
    do: {:error, Error.new(:seshat_no_such_lease, :seshat_leases_renew_absent, path: path)}

  @doc "Releases the holder's lease, held or taken; releasing none is nothing."
  def release(resident_id, path, %Actor{kind: :witness, id: holder}) do
    with {:ok, path} <- Kinds.normalize(resident_id, path),
         do: Scope.resident(resident_id, fn -> released(Store.lease(path), path, holder) end)
  end

  def release(_resident_id, _path, %Actor{}),
    do: {:error, Error.new(:seshat_lease_invalid, :seshat_leases_release_witness_only)}

  defp released(%Lease{holder_id: holder}, path, holder), do: Store.delete_lease(path)

  defp released(%Lease{}, _path, _holder),
    do: {:error, Error.new(:seshat_lease_held, :seshat_leases_release_other)}

  defp released(nil, _path, _holder), do: :ok

  @doc "The lease on a path as both parties see it, or nil."
  def lease(resident_id, path) do
    with {:ok, path} <- Kinds.normalize(resident_id, path),
         %Lease{} = lease <- Scope.resident(resident_id, fn -> Store.lease(path) end) do
      view(lease, Clock.now())
    else
      _none -> nil
    end
  end

  @doc "Every lease on the resident's library, held or taken."
  def list(resident_id) do
    now = Clock.now()
    resident_id |> Scope.resident(fn -> Store.leases() end) |> Enum.map(&view(&1, now))
  end

  @doc """
  A write through the flow that minds the leases: hers on a path he
  holds waits, or takes a lease gone idle; his on a lease of his renews
  it. Everything else is `Documents.write/5` as it was.
  """
  def write(resident_id, path, content, %Actor{} = actor, opts \\ []) do
    case {actor.kind, Keyword.get(opts, :core, false), Kinds.normalize(resident_id, path)} do
      {:resident, false, {:ok, normal}} ->
        theirs(resident_id, normal, content, actor, opts)

      {:witness, false, {:ok, normal}} ->
        with {:ok, written} <- Documents.write(resident_id, normal, content, actor, opts) do
          renew_on_write(resident_id, normal, actor)
          {:ok, written}
        end

      _other ->
        Documents.write(resident_id, path, content, actor, opts)
    end
  end

  # Hers: no lease, or one already taken, and the write goes in; a held
  # one is waited on, and taken when it has gone idle.
  defp theirs(resident_id, path, content, actor, opts) do
    now = Clock.now()

    case Scope.resident(resident_id, fn -> Store.lease(path) end) do
      %Lease{state: "held"} = lease ->
        if takeable?(lease, now),
          do: take(resident_id, lease, content, actor, opts, now),
          else: wait(resident_id, lease, now)

      _none_or_taken ->
        Documents.write(resident_id, path, content, actor, opts)
    end
  end

  defp wait(resident_id, lease, now) do
    lease =
      Scope.resident(resident_id, fn ->
        Store.put_lease(%{lease | waiting_at: lease.waiting_at || now})
      end)

    {:ok,
     %{
       path: lease.path,
       kind: Kinds.kind_of(resident_id, lease.path).kind,
       changed: false,
       indexed: false,
       written: false,
       waiting: view(lease, now)
     }}
  end

  defp take(resident_id, lease, content, actor, opts, now) do
    with {:ok, kept_at} <- keep_draft(resident_id, lease, now) do
      taken =
        Scope.resident(resident_id, fn ->
          Store.put_lease(%{
            lease
            | state: "taken",
              waiting_at: lease.waiting_at || now,
              taken_at: now,
              kept_at: kept_at,
              draft: nil
          })
        end)

      with {:ok, written} <- Documents.write(resident_id, lease.path, content, actor, opts),
           do: {:ok, Map.merge(written, %{written: true, took: view(taken, now)})}
    end
  end

  # His draft, when it is not the file's words already, kept as a
  # document of his before her write goes in: never lost.
  defp keep_draft(_resident_id, %Lease{draft: nil}, _now), do: {:ok, nil}

  defp keep_draft(resident_id, %Lease{} = lease, now) do
    if lease.draft == on_disk(resident_id, lease.path) do
      {:ok, nil}
    else
      kept = drafts_path(lease.path, now)

      with {:ok, _} <-
             Documents.write(
               resident_id,
               kept,
               lease.draft,
               Actor.new(:witness, lease.holder_id),
               note:
                 "his unsaved draft of #{lease.path}, kept when her write took his idle lease (seshat#55)"
             ),
           do: {:ok, kept}
    end
  end

  # `human/drafts/<dir>/<name>-<stamp><ext>`: his folder, the path it was
  # a draft of, and when it was kept, so a second kept draft never
  # overwrites the first.
  defp drafts_path(path, now) do
    ext = Path.extname(path)
    stamp = Calendar.strftime(now, "%Y%m%d%H%M%S")
    Path.join(["human", "drafts", Path.rootname(path) <> "-" <> stamp <> ext])
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp on_disk(resident_id, path) do
    with {:ok, dir} <- SimaQian.repository_dir(resident_id),
         {:ok, words} <- File.read(Path.join(dir, path)) do
      words
    else
      _absent -> nil
    end
  end

  defp renew_on_write(resident_id, path, %Actor{id: holder}) do
    Scope.resident(resident_id, fn ->
      case Store.lease(path) do
        %Lease{state: "held", holder_id: ^holder} = lease ->
          Store.put_lease(%{lease | renewed_at: Clock.now(), draft: nil})

        _none ->
          :ok
      end
    end)
  end

  defp takeable?(%Lease{renewed_at: renewed}, now),
    do: DateTime.compare(now, DateTime.add(renewed, idle(), :second)) != :lt

  defp idle, do: Config.fetch!(:seshat, :lease_idle_seconds)

  @doc false
  def view(%Lease{} = l, now) do
    takeable_at = DateTime.add(l.renewed_at, idle(), :second)

    %{
      path: l.path,
      holder_id: l.holder_id,
      state: l.state,
      acquired_at: l.acquired_at,
      renewed_at: l.renewed_at,
      takeable_at: takeable_at,
      takeable: l.state == "held" and DateTime.compare(now, takeable_at) != :lt,
      waiting_at: l.waiting_at,
      has_draft: is_binary(l.draft),
      taken_at: l.taken_at,
      kept_at: l.kept_at
    }
  end
end
