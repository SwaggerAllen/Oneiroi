defmodule Oneiroi.Identity do
  @moduledoc """
  Accounts, authentication, sessions, stewardship (spec §6.1).

  A password and, once enrolled, a TOTP second factor; sessions as random
  ids with only the hash stored, thirty days; API tokens the same way;
  stewardship as a relation from an account to a resident with a start
  and an end, written by this system when a resident is created or custody
  moves. Failed logins slow down rather than lock out.

  Two reads here take the platform scope by name (conventions §12),
  because the principal is not known until they answer: the lookup of an
  account by email at login, and of a session or token by its hash on a
  request. Everything after runs under the account's own scope.
  """
  use Oneiroi.System, slug: :identity

  use Boundary,
    top_level?: true,
    deps: [
      Oneiroi,
      Commanded,
      Commanded.Commands.Router,
      Commanded.Event.Handler,
      Commanded.Middleware,
      Commanded.Projections.Ecto,
      Commanded.Serialization.JsonDecoder,
      Ecto,
      Ecto.Changeset,
      Ecto.Multi,
      Ecto.Query,
      Ecto.Schema,
      Jason,
      Oneiroi.Resident,
      Argon2,
      NimbleTOTP
    ],
    exports: [
      Accounts,
      Error,
      Principal,
      Router,
      Events.AccountCreated,
      Events.SessionOpened,
      Events.SessionClosed,
      Events.SecondFactorEnrolled,
      Events.TokenIssued,
      Events.TokenRevoked,
      Events.StewardshipStarted,
      Events.StewardshipEnded,
      Store,
      Store.Account,
      Store.Stewardship,
      Throttle
    ]

  alias Oneiroi.Identity.Accounts

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:login_delay_ms, "IDENTITY_LOGIN_DELAY_MS",
       cast: :integer,
       default: "200",
       tag: :bound,
       usage:
         "the base delay after a failed login, doubled per failure up to five seconds (Oneiroi.Identity.Throttle)"},
      {:session_ttl_days, "IDENTITY_SESSION_TTL_DAYS",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage: "how long a session lives from its opening, as the owner UI does today (spec §6.1)"},
      {:totp_issuer, "IDENTITY_TOTP_ISSUER",
       default: "Oneiroi",
       usage: "the issuer an authenticator app shows for an enrolled second factor"}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Identity.Events.AccountCreated, 1},
      {Oneiroi.Identity.Events.SecondFactorEnrolled, 1},
      {Oneiroi.Identity.Events.SessionOpened, 1},
      {Oneiroi.Identity.Events.SessionClosed, 1},
      {Oneiroi.Identity.Events.TokenIssued, 1},
      {Oneiroi.Identity.Events.TokenRevoked, 1},
      {Oneiroi.Identity.Events.StewardshipStarted, 1},
      {Oneiroi.Identity.Events.StewardshipEnded, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:identity_invalid_credentials, "the email, password or code did not verify",
       remedy: "try again; the delay grows with each failure and nothing locks"},
      {:identity_second_factor_required,
       "the account has a second factor and the code was not supplied",
       remedy: "send the code from the authenticator app"},
      {:identity_not_a_principal, "the session or token resolves to no live account",
       remedy: "log in again, or issue a new token"}
    ]
  end

  @impl Oneiroi.Component
  def processes do
    [{:identity_throttle, :local}]
  end

  @impl Oneiroi.Component
  def children do
    [
      # The throttle takes the component as an option rather than naming
      # it, so the guardrail lookup does not close a cycle with this list.
      {Oneiroi.Identity.Throttle, component: __MODULE__},
      Oneiroi.Identity.Projectors.Accounts,
      Oneiroi.Identity.Handlers.Stewardship
    ]
  end

  @doc "Creates an account with a password; the setup task's and, later, sign-up's door."
  @spec create_account(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(create_account(email, password, actor), do: Accounts.create(email, password, actor))

  @doc "Verifies credentials and opens a session; the raw session id is returned once."
  @spec login(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t(), Oneiroi.Identity.Principal.t()} | {:error, term()}
  defexport(login(email, password, code), do: Accounts.login(email, password, code))

  @doc "Closes the session the raw id names."
  @spec logout(String.t()) :: :ok | {:error, term()}
  defexport(logout(raw_session), do: Accounts.logout(raw_session))

  @doc "The principal a raw session id resolves to, if it is live."
  @spec authenticate_session(String.t()) :: {:ok, Oneiroi.Identity.Principal.t()} | :error
  defexport(authenticate_session(raw), do: Accounts.authenticate_session(raw))

  @doc "The principal a raw API token resolves to, if it is live."
  @spec authenticate_token(String.t()) :: {:ok, Oneiroi.Identity.Principal.t()} | :error
  defexport(authenticate_token(raw), do: Accounts.authenticate_token(raw))

  @doc "Enrolls a TOTP second factor; the secret and its otpauth URI are returned once."
  @spec enroll_second_factor(String.t(), Oneiroi.Actor.t()) :: {:ok, map()} | {:error, term()}
  defexport(enroll_second_factor(account_id, actor),
    do: Accounts.enroll_second_factor(account_id, actor)
  )

  @doc "Issues an API token for scripts; the raw token is returned once."
  @spec issue_token(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t(), String.t()} | {:error, term()}
  defexport(issue_token(account_id, label, actor),
    do: Accounts.issue_token(account_id, label, actor)
  )

  @doc "Revokes a token by its hash."
  @spec revoke_token(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(revoke_token(account_id, token_hash, actor),
    do: Accounts.revoke_token(account_id, token_hash, actor)
  )

  @doc "The resident ids an account currently stewards."
  @spec stewarded_residents(String.t()) :: [String.t()]
  defexport(stewarded_residents(account_id), do: Accounts.stewarded_residents(account_id))
end
