defmodule Oneiroi.Xenia.ProfilesLedger do
  @moduledoc """
  The profiles a resident's routes read through (xenia#19), on
  `profiles-<resident_id>`: the witness's alone to make, name, revoke
  and restore (Lily's lean, his to change: a profile is a real sign-in).
  This stream is never exported: credentials have one home.
  """

  alias Oneiroi.Xenia.Commands
  alias Oneiroi.Xenia.Error
  alias Oneiroi.Xenia.Events

  defstruct revoked: MapSet.new()

  def execute(%__MODULE__{}, %{actor: %{kind: k}}) when k != :witness,
    do: {:error, Error.new(:xenia_not_allowed, :xenia_profiles_ledger_steward)}

  def execute(%__MODULE__{}, %Commands.SetProfile{} = c),
    do: %Events.ProfileSet{
      actor: c.actor,
      at: c.at,
      id: c.id,
      key: c.key,
      profile: c.profile,
      note: c.note
    }

  def execute(%__MODULE__{revoked: r}, %Commands.RevokeProfile{} = c) do
    if MapSet.member?(r, c.key),
      do: [],
      else: %Events.ProfileRevoked{actor: c.actor, at: c.at, id: c.id, key: c.key, note: c.note}
  end

  def execute(%__MODULE__{revoked: r}, %Commands.RestoreProfile{} = c) do
    if MapSet.member?(r, c.key),
      do: %Events.ProfileRestored{actor: c.actor, at: c.at, id: c.id, key: c.key, note: c.note},
      else: []
  end

  def apply(%__MODULE__{} = s, %Events.ProfileSet{}), do: s

  def apply(%__MODULE__{} = s, %Events.ProfileRevoked{key: k}),
    do: %{s | revoked: MapSet.put(s.revoked, k)}

  def apply(%__MODULE__{} = s, %Events.ProfileRestored{key: k}),
    do: %{s | revoked: MapSet.delete(s.revoked, k)}
end
