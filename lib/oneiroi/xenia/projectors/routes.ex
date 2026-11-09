defmodule Oneiroi.Xenia.Projectors.Routes do
  @moduledoc "Folds the routes and profiles streams (xenia#19): her routes' descriptors, their runs, and the profiles as the witness keeps them."
  use Oneiroi.Projection, name: "xenia_routes"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Xenia.Events
  alias Oneiroi.Xenia.Store.{Profile, Route, RouteRun}

  fold(%Events.RouteDefined{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :route,
      %Route{
        resident_id: e.id,
        key: e.key,
        descriptor: e.descriptor,
        created_by: by(e.actor),
        updated_by: by(e.actor),
        created_at: e.at,
        updated_at: e.at
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.RouteChanged{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :route,
      from(r in Route, where: r.resident_id == ^e.id and r.key == ^e.key),
      set: [descriptor: e.descriptor, updated_by: by(e.actor), updated_at: e.at]
    )
  end)

  fold(%Events.RouteAsked{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :run,
      %RouteRun{
        resident_id: e.id,
        number: e.number,
        key: e.key,
        state: "open",
        note: e.note,
        asked_by: by(e.actor),
        asked_at: e.at
      },
      on_conflict: :nothing
    )
  end)

  fold(%Events.RouteLanded{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :run,
      from(r in RouteRun, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [state: "landed", path: e.path, done_at: e.at]
    )
  end)

  fold(%Events.RouteFailed{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :run,
      from(r in RouteRun, where: r.resident_id == ^e.id and r.number == ^e.number),
      set: [state: "failed", reason: e.reason, done_at: e.at]
    )
  end)

  fold(%Events.ProfileSet{} = e, _metadata, fn multi ->
    # Decoded from the store its keys are atoms; as dispatched, strings.
    p = Map.new(e.profile || %{}, fn {k, v} -> {to_string(k), v} end)

    Multi.insert(
      multi,
      :profile,
      %Profile{
        resident_id: e.id,
        key: e.key,
        label: p["label"],
        origin: p["origin"],
        signed_in_as: p["signed_in_as"],
        revoked: false,
        note: e.note,
        set_at: e.at
      },
      on_conflict: {:replace, [:label, :origin, :signed_in_as, :note, :set_at]},
      conflict_target: [:resident_id, :key]
    )
  end)

  fold(%Events.ProfileRevoked{} = e, _metadata, fn multi -> revoked(multi, e, true) end)
  fold(%Events.ProfileRestored{} = e, _metadata, fn multi -> revoked(multi, e, false) end)

  defp revoked(multi, e, revoked?) do
    Multi.insert(
      multi,
      :profile,
      %Profile{resident_id: e.id, key: e.key, revoked: revoked?, note: e.note, set_at: e.at},
      on_conflict: {:replace, [:revoked, :note, :set_at]},
      conflict_target: [:resident_id, :key]
    )
  end

  defp by(%{kind: kind}), do: to_string(kind)
  defp by(%{"kind" => kind}), do: to_string(kind)
  defp by(_none), do: nil
end
