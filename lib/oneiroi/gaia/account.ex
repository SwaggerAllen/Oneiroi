defmodule Oneiroi.Gaia.Account do
  @moduledoc """
  The account aggregate on `account-<id>` (spec §3.1). Pure: no clock,
  no randomness, no ids minted here; every instant and every hash arrives
  on the command (conventions §6).
  """

  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Events

  defstruct [
    :id,
    :email,
    :password_hash,
    :second_factor,
    key?: false,
    sessions: MapSet.new(),
    tokens: MapSet.new(),
    witnessings: MapSet.new()
  ]

  @type t :: %__MODULE__{}

  # ---- execute ----

  def execute(%__MODULE__{id: nil}, %Commands.CreateAccount{} = c) do
    %Events.AccountCreated{
      actor: c.actor,
      at: c.at,
      id: c.id,
      email: c.email,
      password_hash: c.password_hash
    }
  end

  def execute(%__MODULE__{id: id}, %Commands.CreateAccount{}),
    do: {:error, Error.new(:gaia_account_exists, :gaia_account_create_exists, account_id: id)}

  def execute(%__MODULE__{id: nil}, command),
    do:
      {:error,
       Error.new(:gaia_no_such_account, :gaia_account_absent, account_id: Map.get(command, :id))}

  def execute(%__MODULE__{} = _a, %Commands.EnrollSecondFactor{} = c) do
    %Events.SecondFactorEnrolled{
      actor: c.actor,
      at: c.at,
      id: c.id,
      secret_ciphertext: c.secret_ciphertext
    }
  end

  def execute(%__MODULE__{} = _a, %Commands.OpenSession{} = c) do
    %Events.SessionOpened{
      actor: c.actor,
      at: c.at,
      id: c.id,
      session_hash: c.session_hash,
      expires_at: c.expires_at
    }
  end

  def execute(%__MODULE__{sessions: sessions}, %Commands.CloseSession{} = c) do
    if MapSet.member?(sessions, c.session_hash),
      do: %Events.SessionClosed{actor: c.actor, at: c.at, id: c.id, session_hash: c.session_hash},
      else: {:error, Error.new(:gaia_not_a_principal, :gaia_account_close_session_absent)}
  end

  def execute(%__MODULE__{}, %Commands.IssueToken{} = c) do
    %Events.TokenIssued{
      actor: c.actor,
      at: c.at,
      id: c.id,
      token_hash: c.token_hash,
      label: c.label
    }
  end

  def execute(%__MODULE__{tokens: tokens}, %Commands.RevokeToken{} = c) do
    if MapSet.member?(tokens, c.token_hash),
      do: %Events.TokenRevoked{actor: c.actor, at: c.at, id: c.id, token_hash: c.token_hash},
      else: {:error, Error.new(:gaia_no_such_token, :gaia_account_revoke_token_absent)}
  end

  # Storing over a stored key is the rotation; the log keeps both.
  def execute(%__MODULE__{}, %Commands.StoreKey{} = c) do
    %Events.KeyStored{actor: c.actor, at: c.at, id: c.id, key_ciphertext: c.key_ciphertext}
  end

  def execute(%__MODULE__{key?: true}, %Commands.RevokeKey{} = c),
    do: %Events.KeyRevoked{actor: c.actor, at: c.at, id: c.id}

  def execute(%__MODULE__{}, %Commands.RevokeKey{}),
    do: {:error, Error.new(:gaia_no_key, :gaia_account_revoke_key_absent)}

  # Idempotent on purpose: the witnessing handler replays (conventions §7).
  def execute(%__MODULE__{witnessings: s}, %Commands.StartWitnessing{} = c) do
    if MapSet.member?(s, c.resident_id),
      do: [],
      else: %Events.WitnessingStarted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id
      }
  end

  def execute(%__MODULE__{witnessings: s}, %Commands.EndWitnessing{} = c) do
    if MapSet.member?(s, c.resident_id),
      do: %Events.WitnessingEnded{actor: c.actor, at: c.at, id: c.id, resident_id: c.resident_id},
      else: []
  end

  # ---- apply ----

  def apply(%__MODULE__{} = a, %Events.AccountCreated{} = e) do
    %{a | id: e.id, email: e.email, password_hash: e.password_hash}
  end

  def apply(%__MODULE__{} = a, %Events.SecondFactorEnrolled{} = e),
    do: %{a | second_factor: e.secret_ciphertext}

  def apply(%__MODULE__{} = a, %Events.SessionOpened{} = e),
    do: %{a | sessions: MapSet.put(a.sessions, e.session_hash)}

  def apply(%__MODULE__{} = a, %Events.SessionClosed{} = e),
    do: %{a | sessions: MapSet.delete(a.sessions, e.session_hash)}

  def apply(%__MODULE__{} = a, %Events.TokenIssued{} = e),
    do: %{a | tokens: MapSet.put(a.tokens, e.token_hash)}

  def apply(%__MODULE__{} = a, %Events.TokenRevoked{} = e),
    do: %{a | tokens: MapSet.delete(a.tokens, e.token_hash)}

  def apply(%__MODULE__{} = a, %Events.KeyStored{}), do: %{a | key?: true}
  def apply(%__MODULE__{} = a, %Events.KeyRevoked{}), do: %{a | key?: false}

  def apply(%__MODULE__{} = a, %Events.WitnessingStarted{} = e),
    do: %{a | witnessings: MapSet.put(a.witnessings, e.resident_id)}

  def apply(%__MODULE__{} = a, %Events.WitnessingEnded{} = e),
    do: %{a | witnessings: MapSet.delete(a.witnessings, e.resident_id)}
end
