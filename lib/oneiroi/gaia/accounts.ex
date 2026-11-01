defmodule Oneiroi.Gaia.Accounts do
  @moduledoc """
  Identity's service functions, behind `Oneiroi.Gaia`'s exports. The
  command edge: ids, hashes, random ids and instants are made here and
  handed to the aggregate, which stays pure (conventions §6).
  """

  alias Oneiroi.Actor
  alias Oneiroi.Apsu.Clock
  alias Oneiroi.Apsu.Vault
  alias Oneiroi.Config
  alias Oneiroi.Config.Secret
  alias Oneiroi.Gaia.Commands
  alias Oneiroi.Gaia.Error
  alias Oneiroi.Gaia.Principal
  alias Oneiroi.Gaia.Router
  alias Oneiroi.Gaia.Store
  alias Oneiroi.Gaia.Throttle
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

    with {:ok, _events} <- dispatch(command), do: {:ok, id}
  end

  @doc """
  Verifies the credentials and opens a session. The lookup runs under the
  platform scope by name: the principal is not known until it answers.
  On a failure to verify the throttle's delay is applied before
  answering, and a missing account costs a hash verification too, so an
  email's existence cannot be read off the clock.

  Credentials that verified and a session the store could not open are
  `gaia_session_unavailable`, unthrottled: the steward's login answered
  401 invalid credentials during a deploy's overlap, when the session's
  dispatch timed out waiting on a projector, and each retry of the right
  password grew the delay.
  """
  def login(email, password, code) do
    now = Clock.now()
    account = Scope.platform(fn -> Store.account_by_email(email) end)

    with {:ok, account} <- verify_password(account, password),
         :ok <- verify_second_factor(account, code) do
      Throttle.clear(email)
      open_session(account, now)
    else
      :code_required ->
        slow(email)
        {:error, Error.new(:gaia_second_factor_required, :gaia_login_code_missing)}

      # One site for an unknown email, a wrong password and a wrong code:
      # the site rides the 401, and three would tell apart what the
      # clock is kept from telling.
      :invalid ->
        slow(email)
        {:error, Error.new(:gaia_invalid_credentials, :gaia_login_credentials_invalid)}
    end
  end

  defp open_session(account, now) do
    raw = random()

    command = %Commands.OpenSession{
      actor: Actor.new(:witness, account.id),
      at: now,
      id: account.id,
      session_hash: hash(raw),
      expires_at: DateTime.add(now, Config.fetch!(:gaia, :session_ttl_days), :day)
    }

    case Router.dispatch(command) do
      {:ok, _events} ->
        {:ok, raw, %Principal{account_id: account.id, email: account.email, via: :session}}

      {:error, reason} ->
        {:error, Error.caught(:gaia_session_unavailable, :gaia_login_session_not_opened, reason)}
    end
  end

  @doc "Closes the session the raw id names, under the account's scope."
  def logout(raw) do
    now = Clock.now()

    case Scope.platform(fn -> Store.live_session(hash(raw), now) end) do
      nil ->
        {:error, Error.new(:gaia_not_a_principal, :gaia_logout_session_absent)}

      session ->
        command = %Commands.CloseSession{
          actor: Actor.new(:witness, session.account_id),
          at: now,
          id: session.account_id,
          session_hash: session.hash
        }

        with {:ok, _} <- dispatch(command), do: :ok
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

    with {:ok, _} <- dispatch(command) do
      email = Scope.account(account_id, fn -> Store.account(account_id).email end)
      issuer = Config.fetch!(:gaia, :totp_issuer)

      {:ok,
       %{
         secret: Base.encode32(secret, padding: false),
         uri: NimbleTOTP.otpauth_uri("#{issuer}:#{email}", secret, issuer: issuer)
       }}
    end
  end

  @doc """
  Stores the witness's OpenRouter key, encrypted under the vault, on the
  account (spec §6.11). Storing over a stored key is the rotation.
  """
  def store_key(account_id, raw_key, %Actor{} = actor) do
    raw_key = Secret.reveal(raw_key)
    key = if is_binary(raw_key), do: String.trim(raw_key), else: ""

    if key == "" do
      {:error, Error.new(:gaia_key_required, :gaia_store_key_blank)}
    else
      ciphertext = key |> Vault.encrypt() |> Base.encode64()

      command = %Commands.StoreKey{
        actor: actor,
        at: Clock.now(),
        id: account_id,
        key_ciphertext: ciphertext
      }

      with {:ok, _} <- dispatch(command), do: :ok
    end
  end

  def revoke_key(account_id, %Actor{} = actor) do
    command = %Commands.RevokeKey{actor: actor, at: Clock.now(), id: account_id}

    with {:ok, _} <- dispatch(command), do: :ok
  end

  @doc """
  The witness's key, wrapped, for the provider port and nothing else: the
  wrapper's `unwrap/1` at the one call site is the word a reviewer sees.
  """
  def key_for(account_id) do
    Scope.account(account_id, fn ->
      with %{key_ciphertext: ciphertext} when is_binary(ciphertext) <- Store.account(account_id),
           {:ok, key} <- Vault.decrypt(ciphertext) do
        {:ok, Secret.wrap(key)}
      else
        _ -> {:error, Error.new(:gaia_no_key, :gaia_key_for_absent)}
      end
    end)
  end

  @doc "Whether a key is stored, and since when; the status the ledger screen shows."
  def key_status(account_id) do
    Scope.account(account_id, fn ->
      case Store.account(account_id) do
        %{key_ciphertext: c, key_stored_at: at} when is_binary(c) ->
          %{present: true, stored_at: at}

        _ ->
          %{present: false, stored_at: nil}
      end
    end)
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

    with {:ok, _} <- dispatch(command), do: {:ok, raw, hash(raw)}
  end

  def revoke_token(account_id, token_hash, %Actor{} = actor) do
    command = %Commands.RevokeToken{
      actor: actor,
      at: Clock.now(),
      id: account_id,
      token_hash: token_hash
    }

    with {:ok, _} <- dispatch(command), do: :ok
  end

  def witnessed_residents(account_id),
    do: Scope.account(account_id, fn -> Store.witnessed(account_id) end)

  @doc "The sha256 of a raw secret, hex; what the store holds."
  @spec hash(String.t()) :: String.t()
  def hash(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)

  defp random, do: 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp verify_password(nil, _password) do
    Argon2.no_user_verify()
    :invalid
  end

  defp verify_password(account, password) do
    if Argon2.verify_pass(Secret.reveal(password), account.password_hash),
      do: {:ok, account},
      else: :invalid
  end

  defp verify_second_factor(%{second_factor: nil}, _code), do: :ok
  defp verify_second_factor(%{second_factor: _}, nil), do: :code_required

  defp verify_second_factor(%{second_factor: ciphertext}, code) do
    with {:ok, secret} <- Vault.decrypt(ciphertext),
         true <-
           NimbleTOTP.valid?(secret, Secret.reveal(code), time: DateTime.to_unix(Clock.now())) do
      :ok
    else
      _ -> :invalid
    end
  end

  # The aggregate's refusals arrive sited (`Account`); what else a
  # dispatch answers, the actor middleware's refusal or the store's own
  # failure, is wrapped here, once, where it is first matched.
  defp dispatch(command) do
    case Router.dispatch(command) do
      {:ok, events} ->
        {:ok, events}

      {:error, %Error{}} = refused ->
        refused

      {:error, {:refused, problems} = refusal} ->
        {:error,
         Error.caught(:gaia_command_refused, :gaia_accounts_command_refused, refusal,
           problems: problems
         )}

      {:error, reason} ->
        {:error,
         Error.caught(:gaia_dispatch_failed, :gaia_accounts_dispatch_failed, reason,
           command: command.__struct__
         )}
    end
  end

  defp slow(email) do
    delay = Throttle.failed(email, Config.fetch!(:gaia, :login_delay_ms))
    if delay > 0, do: Process.sleep(delay)
    :ok
  end

  @doc "The email of an account by id, platform scope by name."
  def email(account_id) when is_binary(account_id) do
    Scope.platform(fn ->
      case Store.account(account_id) do
        nil -> nil
        account -> account.email
      end
    end)
  end

  def email(_other), do: nil

  @doc "The id of the account with an email, platform scope by name."
  def id_for(email) when is_binary(email) do
    Scope.platform(fn ->
      case Store.account_by_email(email) do
        nil -> nil
        account -> account.id
      end
    end)
  end

  def id_for(_other), do: nil
end
