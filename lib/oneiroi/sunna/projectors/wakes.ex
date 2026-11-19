defmodule Oneiroi.Sunna.Projectors.Wakes do
  @moduledoc "Folds the wake log (sunna#71) into a row a wake: what it carried and when it was read."
  use Oneiroi.Projection, name: "sunna_wakes"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Sunna.Events
  alias Oneiroi.Sunna.Store.Wake

  fold(%Events.WakeManifested{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :wake,
      %Wake{
        resident_id: e.id,
        wake_id: e.wake_id,
        household_id: e.household_id,
        channel: e.channel,
        causes: %{"list" => e.causes || []},
        delivered: e.delivered != false,
        manifested_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:resident_id, :wake_id]
    )
  end)

  fold(%Events.WakeRead{} = e, _metadata, fn multi ->
    Multi.update_all(
      multi,
      :read,
      from(w in Wake, where: w.resident_id == ^e.id and w.wake_id == ^e.wake_id),
      set: [read_at: e.at]
    )
  end)
end
