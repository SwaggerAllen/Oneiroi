defmodule Oneiroi.Kumbukumbu.Projectors.Reacts do
  @moduledoc "Folds the reacts stream (kumbukumbu#56): each react with its target, and when it was told."
  use Oneiroi.Projection, name: "kumbukumbu_reacts"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Kumbukumbu.Events
  alias Oneiroi.Kumbukumbu.Store.React

  fold(%Events.Reacted{} = e, _metadata, fn multi ->
    t = Map.new(e.target || %{}, fn {k, v} -> {to_string(k), v} end)

    Multi.insert(
      multi,
      :react,
      %React{
        resident_id: e.id,
        number: e.number,
        target_kind: t["kind"],
        session_key: t["session_key"],
        turn_ref: t["turn_ref"],
        letter: t["number"],
        path: t["path"],
        document_hash: t["hash"],
        emoji: e.emoji,
        by: by(e.actor),
        reacted_at: e.at
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.ReactsTold{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :told,
      from(r in React,
        where:
          r.resident_id == ^e.id and r.number <= ^e.through and r.by == "witness" and
            is_nil(r.told_at)
      ),
      set: [told_at: e.at, told_in: e.session_key]
    )
  end)

  defp by(%{kind: kind}), do: to_string(kind)
  defp by(%{"kind" => kind}), do: to_string(kind)
end
