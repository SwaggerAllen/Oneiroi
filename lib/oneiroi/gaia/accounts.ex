defmodule Oneiroi.Gaia.Accounts do
  @moduledoc """
  Identity's service functions, behind `Oneiroi.Gaia`'s exports. The
  command edge: ids, hashes, random ids and instants are made here and
  handed to the aggregate, which stays pure (conventions §6).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Config
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Principal
  alias Oneiroi.Gaia.Router
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Gaia.Throttle
  alias Oneiroi.Platform.Clock
  alias Oneiroi.Platform.Vault
  alias Oneiroi.Scope

  @doc "Creates an account; the password is hashed here and only the hash travels."
  def create(email, password, %Actor{} = actor) when is_binary(email) and is_binary(password) do
    id = Ecto.UUID.generate()

    command = %Commands.CreateAccount{
      actor: actor,
      at: Clock.now(),
      id: id,
      email: String.trim(email),
      password_hash: Argon2.hash_pwd_salt(password)
    }

    with {:ok, _events} <- Router.dispatch(command), do: {:ok, id}
  end

  @doc """
  Verifies the credentials and opens a session. The lookup runs under the
  platform scope by name: the principal is not known until it answers.
  On any failure the throttle's delay is applied before answering, and
  a missing account costs a hash verification too, so an email's
  existence cannot be read off the clock.
  """
  def login(email, password, code) do
    now = Clock.now()
    account = Scope.platform(fn -> Store.account_by_email(email) end)

    with {:ok, account} <- verify_password(account, password),
         :ok <- verify_second_factor(account, code),
         raw = random(),
         expires = DateTime.add(now, Config.fetch!(:gaia, :session_ttl_days), :day),
         command = %Commands.OpenSession{
           actor: Actor.new(:steward, account.id),
           at: now,
           id: account.id,
           session_hash: hash(raw),
           expires_at: expires
         },
         {:ok, _events} <- Router.dispatch(command) do
      Throttle.clear(email)
      {:ok, raw, %Principal{account_id: account.id, email: account.email, via: :session}}
    else
      {:error, reason} ->
        slow(email)
        {:error, reason}
    end
  end

  @doc "Closes the session the raw id names, under the account's scope."
  def logout(raw) do
    now = Clock.now()

    case Scope.platform(fn -> Store.live_session(hash(raw), now) end) do
      nil ->
        {:error, :gaia_not_a_principal}

      session ->
        command = %Commands.CloseSession{
          actor: Actor.new(:steward, session.account_id),
          at: now,
          id: session.account_id,
          session_hash: session.hash
        }

        with {:ok, _} <- Router.dispatch(command), do: :ok
    end
  end

  def authenticate_session(raw) when is_binary(raw) do
    now = Clock.now()

    Scope.platform(fn ->
      with %{account_id: account_id} <- Store.live_session(hash(raw), now),
           %{email: email} <- Store.account(account_id) do
        {:ok, %Principal{account_id: account_id, email: email, via: :session}}
      else
        _ -> :error
      end
    end)
  end

  def authenticate_session(_raw), do: :error

  def authenticate_token(raw) when is_binary(raw) do
    Scope.platform(fn ->
      with %{account_id: account_id} <- Store.live_token(hash(raw)),
           %{email: email} <- Store.account(account_id) do
        {:ok, %Principal{account_id: account_id, email: email, via: :token}}
      else
        _ -> :error
      end
    end)
  end

  def authenticate_token(_raw), do: :error

  def enroll_second_factor(account_id, %Actor{} = actor) do
    secret = NimbleTOTP.secret()
    ciphertext = secret |> Vault.encrypt() |> Base.encode64()

    command = %Commands.EnrollSecondFactor{
      actor: actor,
      at: Clock.now(),
      id: account_id,
      secret_ciphertext: ciphertext
    }

    with {:ok, _} <- Router.dispatch(command) do
      email = Scope.account(account_id, fn -> Store.account(account_id).email end)
      issuer = Config.fetch!(:gaia, :totp_issuer)

      {:ok,
       %{
         secret: Base.encode32(secret, padding: false),
         uri: NimbleTOTP.otpauth_uri("#{issuer}:#{email}", secret, issuer: issuer)
       }}
    end
  end

  def issue_token(account_id, label, %Actor{} = actor) do
    raw = random()

    command = %Commands.IssueToken{
      actor: actor,
      at: Clock.now(),
      id: account_id,
      token_hash: hash(raw),
      label: label
    }

    with {:ok, _} <- Router.dispatch(command), do: {:ok, raw, hash(raw)}
  end

  def revoke_token(account_id, token_hash, %Actor{} = actor) do
    command = %Commands.RevokeToken{
      actor: actor,
      at: Clock.now(),
      id: account_id,
      token_hash: token_hash
    }

    with {:ok, _} <- Router.dispatch(command), do: :ok
  end

  def stewarded_residents(account_id),
    do: Scope.account(account_id, fn -> Store.stewarded(account_id) end)

  @doc "The sha256 of a raw secret, hex; what the store holds."
  @spec hash(String.t()) :: String.t()
  def hash(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)

  defp random, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp verify_password(nil, _password) do
    Argon2.no_user_verify()
    {:error, :gaia_invalid_credentials}
  end

  defp verify_password(account, password) do
    if Argon2.verify_pass(password, account.password_hash),
      do: {:ok, account},
      else: {:error, :gaia_invalid_credentials}
  end

  defp verify_second_factor(%{second_factor: nil}, _code), do: :ok

  defp verify_second_factor(%{second_factor: _}, nil),
    do: {:error, :gaia_second_factor_required}

  defp verify_second_factor(%{second_factor: ciphertext}, code) do
    with {:ok, secret} <- Vault.decrypt(ciphertext),
         true <- NimbleTOTP.valid?(secret, code, time: DateTime.to_unix(Clock.now())) do
      :ok
    else
      _ -> {:error, :gaia_invalid_credentials}
    end
  end

  defp slow(email) do
    delay = Throttle.failed(email, Config.fetch!(:gaia, :login_delay_ms))
    if delay > 0, do: Process.sleep(delay)
    :ok
  end
end
