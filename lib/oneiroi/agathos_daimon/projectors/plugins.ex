defmodule Oneiroi.AgathosDaimon.Projectors.Plugins do
  @moduledoc "Folds the plugins streams (agathos-daimon#37) into one row a plugin and one a proposal."
  use Oneiroi.Projection, name: "agathos_daimon_plugins"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.AgathosDaimon.Events
  alias Oneiroi.AgathosDaimon.Store.{Plugin, PluginProposal}

  fold(%Events.PluginProposed{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :proposal,
      %PluginProposal{
        resident_id: e.id,
        number: e.number,
        key: e.key,
        tier: e.tier,
        change: e.change,
        proposed_by: by(e.actor),
        note: e.note,
        proposed_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :number]
    )
  end)

  fold(%Events.PluginAnswered{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :answer,
      from(p in PluginProposal, where: p.resident_id == ^e.id and p.number == ^e.number),
      set: [agreed: e.agree, answer_note: e.note, answered_by: by(e.actor), answered_at: e.at]
    )
  end)

  fold(%Events.PluginChanged{} = e, _metadata, fn multi ->
    {installed, on} =
      case e.change do
        "install" -> {true, false}
        "remove" -> {false, false}
        "on" -> {true, true}
        "off" -> {true, false}
      end

    Multi.insert(
      multi,
      :plugin,
      %Plugin{
        resident_id: e.id,
        key: e.key,
        tier: e.tier,
        installed: installed,
        on: on,
        changed_by: by(e.actor),
        changed_at: e.at
      },
      on_conflict: {:replace, [:tier, :installed, :on, :changed_by, :changed_at]},
      conflict_target: [:resident_id, :key]
    )
  end)

  fold(%Events.PluginsCarriedOver{} = e, _metadata, fn multi ->
    rows =
      for key <- e.keys,
          do: %{
            resident_id: e.id,
            key: key,
            tier: "first_party",
            installed: true,
            on: true,
            carried_over: true,
            changed_by: by(e.actor),
            changed_at: e.at
          }

    Multi.insert_all(multi, :carried, Plugin, rows,
      on_conflict: :nothing,
      conflict_target: [:resident_id, :key]
    )
  end)

  defp by(%{kind: kind}), do: to_string(kind)
  defp by(%{"kind" => kind}), do: kind
end
