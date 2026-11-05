defmodule Oneiroi.Gaia.Invite do
  @moduledoc """
  The invite aggregate (gaia#18), on `invite-<id>`: one code and its SKU,
  the terms a redemption grants a household. Pure; the instant a
  redemption is judged against arrives on the command.

  Issued once, with a note. A redemption is refused when the code is
  revoked, past its expiry, spent (its uses all taken), or already
  redeemed by the same household; each refusal says which, so the
  sign-up form can. Revoked with a note, and a revoked code stays
  revoked.
  """

  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct [:id, :uses, :expires_at, revoked?: false, households: MapSet.new()]

  @plan_limit 60

  def execute(%__MODULE__{id: nil}, %Commands.IssueInvite{} = c) do
    if sku_ok?(c),
      do: %Events.InviteIssued{
        actor: c.actor,
        at: c.at,
        id: c.id,
        code_hash: c.code_hash,
        plan: c.plan,
        price_nanos: c.price_nanos,
        discount_pct: c.discount_pct,
        term_days: c.term_days,
        uses: c.uses,
        expires_at: c.expires_at,
        note: c.note
      },
      else: {:error, Error.new(:gaia_invite_invalid, :gaia_invite_issue_invalid)}
  end

  def execute(%__MODULE__{}, %Commands.IssueInvite{}), do: []

  def execute(%__MODULE__{id: nil}, _command),
    do: {:error, Error.new(:gaia_invite_unknown, :gaia_invite_not_issued)}

  def execute(%__MODULE__{} = i, %Commands.RedeemInvite{} = c) do
    cond do
      i.revoked? ->
        {:error, Error.new(:gaia_invite_revoked, :gaia_invite_redeem_revoked)}

      i.expires_at && DateTime.compare(c.at, i.expires_at) != :lt ->
        {:error, Error.new(:gaia_invite_expired, :gaia_invite_redeem_expired)}

      MapSet.member?(i.households, c.household_id) ->
        {:error, Error.new(:gaia_invite_already_redeemed, :gaia_invite_redeem_twice)}

      MapSet.size(i.households) >= i.uses ->
        {:error, Error.new(:gaia_invite_spent, :gaia_invite_redeem_spent)}

      true ->
        %Events.InviteRedeemed{
          actor: c.actor,
          at: c.at,
          id: c.id,
          household_id: c.household_id
        }
    end
  end

  def execute(%__MODULE__{revoked?: true}, %Commands.RevokeInvite{}), do: []

  def execute(%__MODULE__{}, %Commands.RevokeInvite{} = c) do
    if noted?(c.note),
      do: %Events.InviteRevoked{actor: c.actor, at: c.at, id: c.id, note: c.note},
      else: {:error, Error.new(:gaia_invite_invalid, :gaia_invite_revoke_note)}
  end

  def apply(%__MODULE__{} = i, %Events.InviteIssued{} = e),
    do: %{i | id: e.id, uses: e.uses, expires_at: e.expires_at}

  def apply(%__MODULE__{} = i, %Events.InviteRedeemed{} = e),
    do: %{i | households: MapSet.put(i.households, e.household_id)}

  def apply(%__MODULE__{} = i, %Events.InviteRevoked{}), do: %{i | revoked?: true}

  defp sku_ok?(c) do
    plan_ok?(c.plan) and is_binary(c.code_hash) and amounts_ok?(c) and expiry_ok?(c.expires_at) and
      noted?(c.note)
  end

  defp amounts_ok?(c),
    do:
      count?(c.price_nanos, 0) and c.discount_pct in 0..100 and count?(c.term_days, 1) and
        count?(c.uses, 1)

  defp expiry_ok?(nil), do: true
  defp expiry_ok?(at), do: match?(%DateTime{}, at)

  defp plan_ok?(plan),
    do: is_binary(plan) and String.trim(plan) != "" and String.length(plan) <= @plan_limit

  defp count?(n, least), do: is_integer(n) and n >= least
  defp noted?(note), do: is_binary(note) and String.trim(note) != ""
end
