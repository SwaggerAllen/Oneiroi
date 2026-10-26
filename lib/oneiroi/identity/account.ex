defmodule Oneiroi.Identity.Account do
  @moduledoc """
  The account aggregate on `account-<id>` (spec §3.1). Pure: no clock,
  no randomness, no ids minted here; every instant and every hash arrives
  on the command (conventions §6).
  """

  alias Oneiroi.Identity.Commands
  alias Oneiroi.Identity.Events

  defstruct [
    :id,
    :email,
    :password_hash,
    :second_factor,
    sessions: MapSet.new(),
    tokens: MapSet.new(),
    stewardships: MapSet.new()
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

  def execute(%__MODULE__{}, %Commands.CreateAccount{}), do: {:error, :account_exists}

  def execute(%__MODULE__{id: nil}, _command), do: {:error, :no_such_account}

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
      else: {:error, :no_such_session}
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
      else: {:error, :no_such_token}
  end

  # Idempotent on purpose: the stewardship handler replays (conventions §7).
  def execute(%__MODULE__{stewardships: s}, %Commands.StartStewardship{} = c) do
    if MapSet.member?(s, c.resident_id),
      do: [],
      else: %Events.StewardshipStarted{
        actor: c.actor,
        at: c.at,
        id: c.id,
        resident_id: c.resident_id
      }
  end

  def execute(%__MODULE__{stewardships: s}, %Commands.EndStewardship{} = c) do
    if MapSet.member?(s, c.resident_id),
      do: %Events.StewardshipEnded{actor: c.actor, at: c.at, id: c.id, resident_id: c.resident_id},
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

  def apply(%__MODULE__{} = a, %Events.StewardshipStarted{} = e),
    do: %{a | stewardships: MapSet.put(a.stewardships, e.resident_id)}

  def apply(%__MODULE__{} = a, %Events.StewardshipEnded{} = e),
    do: %{a | stewardships: MapSet.delete(a.stewardships, e.resident_id)}
end
