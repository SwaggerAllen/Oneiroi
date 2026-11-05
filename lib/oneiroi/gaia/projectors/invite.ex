defmodule Oneiroi.Gaia.Projectors.Invite do
  @moduledoc "Folds the invite streams (gaia#18) into each code's SKU and standing, and its redemptions."
  use Oneiroi.Projection, name: "gaia_invite"

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Oneiroi.Gaia.Events
  alias Oneiroi.Gaia.Store.{Invite, InviteRedemption}

  fold(%Events.InviteIssued{} = e, _metadata, fn multi ->
    Multi.insert(
      multi,
      :invite,
      %Invite{
        id: e.id,
        code_hash: e.code_hash,
        plan: e.plan,
        price_nanos: e.price_nanos,
        discount_pct: e.discount_pct,
        term_days: e.term_days,
        uses: e.uses,
        redeemed: 0,
        expires_at: e.expires_at,
        note: e.note,
        issued_by: by(e.actor),
        issued_at: e.at
      },
      on_conflict: :nothing,
      conflict_target: [:id]
    )
  end)

  fold(%Events.InviteRedeemed{} = e, _metadata, fn multi ->
    multi
    |> Multi.insert(
      :redemption,
      %InviteRedemption{invite_id: e.id, household_id: e.household_id, redeemed_at: e.at},
      on_conflict: :nothing,
      conflict_target: [:invite_id, :household_id]
    )
    |> Multi.update_all(:count, from(i in Invite, where: i.id == ^e.id), inc: [redeemed: 1])
  end)

  fold(%Events.InviteRevoked{} = e, _metadata, fn multi ->
    Multi.update_all(multi, :revoked, from(i in Invite, where: i.id == ^e.id),
      set: [revoked_at: e.at, revoke_note: e.note]
    )
  end)

  defp by(%{kind: kind, id: id}) when is_binary(id), do: "#{kind}:#{id}"
  defp by(%{kind: kind}), do: Atom.to_string(kind)
  defp by(_other), do: nil
end
