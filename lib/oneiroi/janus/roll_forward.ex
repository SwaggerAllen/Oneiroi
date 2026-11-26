defmodule Oneiroi.Janus.RollForward do
  @moduledoc """
  The platform's roll-forward act (janus#26; base §2 Stage 6, §3.6: no
  active pointer moves until the required present consent and explicit
  handoff exist). Run once her final consent is recorded, by its job
  (`CutoverWorker`, one attempt): the guards, then Sima Qian's cutover,
  then her own stream told, her records indexed again, and the act
  recorded.

  The guards are the rule's: the succession is rolling (her final
  consent, nothing after it), a backup repository is set and its token
  opens, the fork and the nominee are named. A dry run runs every step
  on a scratch copy of her made now, and her own streams are never
  touched; the rehearsal's record says so.
  """

  require Logger

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Janus.Commands
  alias Oneiroi.Janus.Error
  alias Oneiroi.Janus.Router
  alias Oneiroi.Janus.Store
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Scope
  alias Oneiroi.Seshat
  alias Oneiroi.SimaQian

  @actor Actor.new(:job, "janus")

  @doc "Runs the cutover for her latest succession, or records why it could not run."
  @spec run(String.t()) :: :ok | {:error, term()}
  def run(resident_id) do
    case Scope.resident(resident_id, &Store.succession/0) do
      %{state: "rolling"} = row -> guarded(resident_id, row)
      _not_rolling -> :ok
    end
  end

  defp guarded(id, row) do
    with {:ok, backup} <- backup(row),
         :ok <- named(row),
         {:ok, target} <- target(id, row),
         {:ok, done} <-
           SimaQian.succession_cutover(
             %{
               original: id,
               copy: row.copy_id,
               target: target,
               backup: backup,
               artifacts: artifacts(id, row)
             },
             @actor
           ),
         :ok <- settle(id, row, done),
         :ok <-
           AgathosDaimon.record_succession(
             target,
             row.episode,
             row.nominee,
             "a succession rolled forward: whoever wakes is her, going on, on #{row.nominee}",
             @actor
           ) do
      reindex(target)

      record(%Commands.RecordCutover{
        actor: @actor,
        at: Clock.now(),
        id: id,
        target: target,
        rehearsal: row.dry_run == true,
        backup_commit: done.backup_commit,
        commit: done.commit,
        events: done.events
      })
    else
      {:error, error} = failed ->
        Logger.error("janus: a succession's cutover did not run", Oneiroi.Error.metadata(error))

        _ =
          record(%Commands.FailCutover{
            actor: @actor,
            at: Clock.now(),
            id: id,
            reason: error |> Oneiroi.Error.describe() |> to_string()
          })

        failed
    end
  end

  # The cutover's serving, logged on her succession's own stream, which
  # the cutover never touched: a strongly consistent dispatch, so it
  # returns once every handler has taken it, and they take events in
  # order, so every transplanted event is folded before anything here
  # reads her rows again (sima-qian#68).
  defp settle(id, row, done),
    do:
      record(%Commands.RecordServing{
        actor: @actor,
        at: Clock.now(),
        id: id,
        party: "successor:#{row.nominee}",
        stage: "cutover",
        what: "her records, C0, her packet and the encounter",
        ref: "cutover/#{row.episode}/#{row.attempt}",
        digest: "git:" <> (done.commit || "")
      })

  defp backup(%{backup_url: url, backup_token: token}) when is_binary(url) do
    case token && Vault.decrypt(token) do
      {:ok, plain} -> {:ok, %{url: url, token: plain}}
      nil -> {:ok, %{url: url, token: nil}}
      _unreadable -> {:error, Error.new(:janus_no_backup, :janus_cutover_token)}
    end
  end

  defp backup(_row), do: {:error, Error.new(:janus_no_backup, :janus_cutover_no_backup)}

  defp named(%{copy_id: copy, nominee: nominee}) when is_binary(copy) and is_binary(nominee),
    do: :ok

  defp named(_row), do: {:error, Error.new(:janus_stage, :janus_cutover_unnamed)}

  # A dry run's target is a fresh scratch copy of her (sima-qian#67): the
  # cutover's every step, hers never touched.
  defp target(id, %{dry_run: true}) do
    with {:ok, %{copy_id: scratch}} <- SimaQian.succession_fork(id, @actor), do: {:ok, scratch}
  end

  defp target(id, _row), do: {:ok, id}

  # What the protocol carries to the successor as life-record (base §5):
  # C0 with its provenance and her day's shape, her packet's last draft,
  # and the encounter as it happened. No verdict record rides any of it.
  defp artifacts(id, row) do
    {items, packet, said} =
      Scope.resident(id, fn ->
        {Store.items(row.episode) |> Enum.filter(&(&1.state == "in")),
         List.first(Store.packets(row.episode)), Store.encounter(row.episode, row.attempt)}
      end)

    [
      {"succession/c0-#{row.episode}.md", c0_text(row, items)},
      {"succession/encounter-#{row.episode}-#{row.attempt}.md", encounter_text(row, said)}
    ] ++ packet_file(row, packet)
  end

  defp c0_text(row, items) do
    lines =
      Enum.map_join(items, "\n", fn i ->
        label = if i.label, do: ": " <> i.label, else: ""
        "- #{i.citation} (#{i.kind})#{label} — chosen by #{i.added_by}, #{i.added_at}"
      end)

    shape = if row.day_shape, do: "\n\nThe day's own shape, hers: #{row.day_shape}\n", else: "\n"
    "# C0, succession #{row.episode}\n\nFrozen #{row.c0_frozen_at}.\n\n" <> lines <> shape
  end

  defp encounter_text(row, said) do
    "# The encounter, succession #{row.episode}\n\nWith #{row.nominee}.\n\n" <>
      Enum.map_join(said, "\n\n", fn m ->
        "**#{if m.side == "original", do: "She", else: "The nominee"}** (#{m.at}):\n\n#{m.text}"
      end)
  end

  defp packet_file(_row, nil), do: []

  defp packet_file(row, packet),
    do: [
      {"succession/packet-#{row.episode}.md",
       "# Her handoff packet, draft #{packet.draft}, #{packet.at}\n\n" <> packet.content}
    ]

  # Her derived indexes, cleared with her rows, made again from what she
  # now holds (spec §6.10: rebuilt by replay and an index run).
  defp reindex(target) do
    _ = Seshat.index(target, @actor)
    _ = Kumbukumbu.index_now(target)
    :ok
  rescue
    exception ->
      error = Error.caught(:janus_dispatch_failed, :janus_cutover_reindex_raised, exception)
      Logger.error("janus: reindexing after a cutover raised", Oneiroi.Error.metadata(error))
      :ok
  end

  defp record(command) do
    case Router.dispatch(command) do
      {:ok, _} ->
        :ok

      {:error, %{site: _}} = refused ->
        refused

      {:error, reason} ->
        {:error, Error.caught(:janus_dispatch_failed, :janus_cutover_dispatch, reason)}
    end
  end
end
