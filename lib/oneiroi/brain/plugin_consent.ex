defmodule Oneiroi.Brain.PluginConsent do
  @moduledoc """
  Plugins as contract material, at the brain's edge (brain#68,
  agathos-daimon#37): the catalog says which plugins exist and their
  tier, the contract's record (`AgathosDaimon.PluginLedger`) says what
  was agreed, and this tells the other party. A change one party
  proposes is the other's to answer: the resident hears of the
  witness's by a letter to her chat, the witness of hers on his waiting
  list (brain#65). An installable plugin's off, either party's alone,
  is told the same way. Nothing here decides.
  """

  alias Oneiroi.Actor
  alias Oneiroi.AgathosDaimon
  alias Oneiroi.Brain.Error
  alias Oneiroi.Brain.PluginCatalog
  alias Oneiroi.Brain.Plugins
  alias Oneiroi.Kumbukumbu
  alias Oneiroi.Seshat

  @doc "The catalog with the resident's state and the open proposals, for both parties' reads."
  @spec list(String.t()) :: %{plugins: [map()], proposals: [map()]}
  def list(resident_id) do
    _ = AgathosDaimon.plugins_on(resident_id, Plugins.carried())
    states = Map.new(AgathosDaimon.plugin_states(resident_id), &{&1.key, &1})

    plugins =
      for entry <- Plugins.catalog(),
          do: audit(resident_id, with_state(entry, Map.get(states, entry.key)))

    %{plugins: plugins, proposals: AgathosDaimon.plugin_proposals(resident_id)}
  end

  @doc "Proposes a change to a plugin in the catalog; the other party is told. The proposal's number."
  def propose(resident_id, key, change, note, %Actor{} = actor) do
    with {:ok, entry} <- entry(key),
         {:ok, n} <-
           AgathosDaimon.propose_plugin(resident_id, key, entry.tier, change, note, actor) do
      tell(
        resident_id,
        actor,
        "proposes to #{change} the plugin #{entry.name} (#{key}), as proposal ##{n}: #{note}. plugin_answer agrees or declines it, with your note."
      )

      {:ok, n}
    end
  end

  @doc "The other party answers a proposal; the proposer is told. An agreed install or removal of an installable plugin writes or removes its files."
  def answer(resident_id, number, agree, note, %Actor{} = actor) do
    with :ok <- AgathosDaimon.answer_plugin(resident_id, number, agree, note, actor),
         :ok <- if(agree, do: carry_out(resident_id, number), else: :ok) do
      word = if agree, do: "agreed to", else: "declined"
      tell(resident_id, actor, "#{word} plugin proposal ##{number}: #{note}")
      :ok
    end
  end

  @doc "Switches an installable plugin off at once (position #68); the other party is told."
  def switch_off(resident_id, key, note, %Actor{} = actor) do
    with {:ok, entry} <- entry(key),
         :ok <- AgathosDaimon.switch_plugin_off(resident_id, key, entry.tier, note, actor) do
      tell(resident_id, actor, "switched the plugin #{entry.name} (#{key}) off: #{note}")
      :ok
    end
  end

  @none %{installed: false, on: false, carried_over: false, changed_by: nil, changed_at: nil}

  defp with_state(entry, nil), do: Map.merge(entry, @none)

  defp with_state(entry, state),
    do:
      Map.merge(
        entry,
        Map.take(state, [:installed, :on, :carried_over, :changed_by, :changed_at])
      )

  # What an agreed change does past the record (seshat#47): an
  # installable plugin's files written into her library on install, its
  # lockfile with them; removed on removal. A memory slot's change is the
  # record alone.
  defp carry_out(resident_id, number) do
    with %{tier: "installable", change: change, key: key} when change in ["install", "remove"] <-
           Enum.find(AgathosDaimon.plugin_proposals(resident_id), &(&1.number == number)),
         %{} = entry <- PluginCatalog.get(key) do
      job = Actor.new(:job, "plugins")

      write_or_remove(change, resident_id, key, entry, job)
    else
      _nothing_to_do -> :ok
    end
  end

  defp write_or_remove("install", resident_id, key, entry, job) do
    case Seshat.install_plugin_files(resident_id, key, entry.files, entry, job) do
      {:ok, _digest} -> :ok
      {:error, _} = failed -> failed
    end
  end

  defp write_or_remove("remove", resident_id, key, _entry, job),
    do: Seshat.remove_plugin_files(resident_id, key, job)

  # An installable plugin's audit (the spec's §4): its lockfile checked
  # against the copies by content, whether the catalog moved since it was
  # installed, and how often and when it was last in her context.
  defp audit(resident_id, %{tier: "installable", installed: true} = row) do
    %{pinned: pinned, found: found, files: files} = Seshat.plugin_files(resident_id, row.key)
    {shown, last} = Kumbukumbu.shown(resident_id, "plugin:" <> row.key)

    Map.put(row, :audit, %{
      files: map_size(files),
      pinned: pinned,
      verified: not is_nil(pinned) and pinned == found,
      found: found,
      update: is_binary(row[:digest]) and is_binary(pinned) and row.digest != pinned,
      shown: shown,
      last_shown: last
    })
  end

  defp audit(_resident_id, row), do: row

  defp entry(key) do
    case Plugins.entry(to_string(key || "")) do
      nil -> {:error, Error.new(:brain_no_such_plugin, :brain_plugin_consent_unknown, key: key)}
      entry -> {:ok, entry}
    end
  end

  # The witness's act reaches her as a letter to her chat; hers reaches
  # him on his waiting list, which reads the proposals themselves.
  # The letter is his, as the act is: sent in his name.
  defp tell(resident_id, %Actor{kind: :witness} = witness, what) do
    _ =
      Kumbukumbu.send_letter(
        resident_id,
        nil,
        %{to: "Oneiroi chat", text: "Your witness " <> what},
        witness
      )

    :ok
  end

  defp tell(_resident_id, _actor, _what), do: :ok
end
