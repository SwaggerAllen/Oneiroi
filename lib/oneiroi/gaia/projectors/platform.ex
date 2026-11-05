defmodule Oneiroi.Gaia.Projectors.Platform do
  @moduledoc "Folds the platform stream (gaia#16) into the front door's row and the roles held."
  use Oneiroi.Projection, name: "gaia_platform"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Store.{Gate, Role}

  fold(%Events.GateSet{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :gate,
      %Gate{key: "door", state: e.state, note: e.note, set_by: by(e.actor), set_at: e.at},
      on_conflict: {:replace, [:state, :note, :set_by, :set_at]},
      conflict_target: [:key]
    )
  end)

  fold(%Events.RoleGranted{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :role,
      %Role{
        account_id: e.account_id,
        role: e.role,
        note: e.note,
        granted_by: by(e.actor),
        granted_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:account_id, :role]
    )
  end)

  fold(%Events.RoleRevoked{} = e, _metadata, fn multi ->
    Multi.delete_all(
      multi,
      :role,
      from(r in Role, where: r.account_id == ^e.account_id and r.role == ^e.role)
    )
  end)

  defp by(%{kind: kind, id: id}) when is_binary(id), do: "#{kind}:#{id}"
  defp by(%{kind: kind}), do: Atom.to_string(kind)
  defp by(_other), do: nil
end
