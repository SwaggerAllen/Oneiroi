defmodule Oneiroi.Gaia.Platform do
  @moduledoc """
  The platform aggregate (gaia#16), one stream: the front door's state
  and the roles that may change it. Pure, and it is where the authority
  is checked, so no caller can skip it.

  - The gate is `closed`, `invite` or `open`; only a super admin sets it,
    with a note.
  - A role is `super_admin` (the operator: the gate, the roles, global
    permissions) or `admin` (the scoped tier). Only a super admin grants
    or revokes one, with a note, except the first grant: while no super
    admin exists, the platform itself may grant the founding account
    super admin, once; and the server's console may grant and revoke
    any role (gaia#22), for when the operator is the wrong account or
    locked out. The last super admin cannot be revoked, so the door
    always has a keeper; a transfer is a grant, then a revoke.
  """

  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct gate: "closed", roles: MapSet.new(), boots: 0, commit: nil

  @gates ~w(closed invite open)
  @roles ~w(super_admin admin)

  def execute(%__MODULE__{} = p, %Commands.SetGate{} = c) do
    cond do
      not super_admin?(p, c.actor) ->
        {:error, Error.new(:gaia_not_an_operator, :gaia_platform_gate_not_operator)}

      c.state not in @gates ->
        {:error, Error.new(:gaia_platform_invalid, :gaia_platform_gate_state, gates: @gates)}

      not noted?(c.note) ->
        {:error, Error.new(:gaia_platform_invalid, :gaia_platform_gate_note)}

      c.state == p.gate ->
        []

      true ->
        %Events.GateSet{actor: c.actor, at: c.at, id: c.id, state: c.state, note: c.note}
    end
  end

  # The triage desk (gaia#23): a super admin's, or the console's, with a
  # note; a slug is a resident's, checked against the residents by the
  # service before it gets here.
  def execute(%__MODULE__{} = p, %Commands.SetTriageResident{} = c) do
    cond do
      not (super_admin?(p, c.actor) or console?(c.actor)) ->
        {:error, Error.new(:gaia_not_an_operator, :gaia_platform_triage_not_operator)}

      not noted?(c.note) or not (is_nil(c.slug) or is_binary(c.slug)) ->
        {:error, Error.new(:gaia_platform_invalid, :gaia_platform_triage_invalid)}

      true ->
        %Events.TriageResidentSet{actor: c.actor, at: c.at, note: c.note, id: c.id, slug: c.slug}
    end
  end

  def execute(%__MODULE__{} = p, %Commands.GrantRole{} = c) do
    cond do
      not may_grant?(p, c) ->
        {:error, Error.new(:gaia_not_an_operator, :gaia_platform_grant_not_operator)}

      c.role not in @roles ->
        {:error, Error.new(:gaia_platform_invalid, :gaia_platform_role_unknown, roles: @roles)}

      not (is_binary(c.account_id) and noted?(c.note)) ->
        {:error, Error.new(:gaia_platform_invalid, :gaia_platform_grant_invalid)}

      MapSet.member?(p.roles, {c.account_id, c.role}) ->
        []

      true ->
        role_event(Events.RoleGranted, c)
    end
  end

  def execute(%__MODULE__{} = p, %Commands.RevokeRole{} = c) do
    cond do
      not (super_admin?(p, c.actor) or console?(c.actor)) ->
        {:error, Error.new(:gaia_not_an_operator, :gaia_platform_revoke_not_operator)}

      not MapSet.member?(p.roles, {c.account_id, c.role}) ->
        []

      not noted?(c.note) ->
        {:error, Error.new(:gaia_platform_invalid, :gaia_platform_revoke_note)}

      c.role == "super_admin" and holders(p, "super_admin") == [c.account_id] ->
        last_keeper()

      true ->
        role_event(Events.RoleRevoked, c)
    end
  end

  # A boot (gaia#21): the platform's own act, recorded by the platform.
  def execute(%__MODULE__{} = p, %Commands.RecordBoot{} = c) do
    if c.actor.kind == :platform do
      %Events.BootRecorded{
        actor: c.actor,
        at: c.at,
        id: c.id,
        number: p.boots + 1,
        commit: c.commit,
        previous: p.commit,
        changed: p.boots > 0 and c.commit != p.commit
      }
    else
      {:error, Error.new(:gaia_not_an_operator, :gaia_platform_boot_not_platform)}
    end
  end

  def apply(%__MODULE__{} = p, %Events.GateSet{} = e), do: %{p | gate: e.state}
  def apply(%__MODULE__{} = p, %Events.TriageResidentSet{}), do: p

  def apply(%__MODULE__{} = p, %Events.BootRecorded{} = e),
    do: %{p | boots: e.number, commit: e.commit}

  def apply(%__MODULE__{} = p, %Events.RoleGranted{} = e),
    do: %{p | roles: MapSet.put(p.roles, {e.account_id, e.role})}

  def apply(%__MODULE__{} = p, %Events.RoleRevoked{} = e),
    do: %{p | roles: MapSet.delete(p.roles, {e.account_id, e.role})}

  defp role_event(module, c),
    do:
      struct(module,
        actor: c.actor,
        at: c.at,
        id: c.id,
        account_id: c.account_id,
        role: c.role,
        note: c.note
      )

  # A super admin grants; so does the platform, once, for the founding
  # account, while no super admin exists; and so does the server's
  # console (gaia#22), whose holder already holds the machine.
  defp may_grant?(p, c),
    do:
      super_admin?(p, c.actor) or console?(c.actor) or
        (founding?(c) and holders(p, "super_admin") == [])

  # The server's console (gaia#22): a shell on the running release. It
  # is the platform acting at a person's hand, named apart from the
  # platform's own jobs so the record says which.
  defp console?(%{kind: :platform, id: "console"}), do: true
  defp console?(_actor), do: false

  defp founding?(c), do: c.actor.kind == :platform and c.role == "super_admin"

  defp super_admin?(p, %{kind: :witness, id: id}),
    do: MapSet.member?(p.roles, {id, "super_admin"})

  defp super_admin?(_p, _actor), do: false

  defp holders(p, role), do: for({id, ^role} <- p.roles, do: id)

  defp noted?(note), do: is_binary(note) and String.trim(note) != ""

  defp last_keeper,
    do: {:error, Error.new(:gaia_last_super_admin, :gaia_platform_revoke_last_keeper)}
end
