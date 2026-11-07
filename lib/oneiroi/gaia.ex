defmodule Oneiroi.Gaia do
  @moduledoc """
  Accounts, authentication, sessions, witnessing (spec §6.1).

  A password and, once enrolled, a TOTP second factor; sessions as random
  ids with only the hash stored, thirty days; API tokens the same way;
  witnessing as a relation from an account to a resident with a start
  and an end, written by this system when a resident is created or custody
  moves. Failed logins slow down rather than lock out.

  Two reads here take the platform scope by name (conventions §12),
  because the principal is not known until they answer: the lookup of an
  account by email at login, and of a session or token by its hash on a
  request. Everything after runs under the account's own scope.
  """
  use Oneiroi.System, slug: :gaia

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
      Oneiroi.AgathosDaimon,
      Argon2,
      NimbleTOTP,
      Req,
      Req.Response
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
      Events.KeyStored,
      Events.KeyRevoked,
      Events.WitnessingStarted,
      Events.WitnessingEnded,
      Store,
      Store.Account,
      Store.Witnessing,
      Throttle,
      Push,
      Push.WebPush,
      Push.Fake,
      Events.PushSubscribed,
      Events.PushUnsubscribed,
      Events.GateSet,
      Events.BootRecorded,
      Boots,
      Events.RoleGranted,
      Events.RoleRevoked,
      Door,
      PlatformRouter,
      Events.HouseholdFounded,
      Events.HouseholdWitnessJoined,
      Events.HouseholdResidentJoined,
      Events.HouseholdResidentLeft,
      Events.HouseholdTermsGranted,
      Households,
      HouseholdRouter,
      Events.InviteIssued,
      Events.InviteRedeemed,
      Events.InviteRevoked,
      Invites,
      InviteRouter,
      Signup,
      Events.FeedbackFiled,
      Events.FeedbackMoved,
      Feedbacks,
      FeedbackRouter,
      Store.Feedback
    ]

  alias Oneiroi.Gaia.Accounts
  alias Oneiroi.Gaia.Boots
  alias Oneiroi.Gaia.Door
  alias Oneiroi.Gaia.Feedbacks
  alias Oneiroi.Gaia.Households
  alias Oneiroi.Gaia.Invites
  alias Oneiroi.Gaia.Push
  alias Oneiroi.Gaia.Signup

  @impl Oneiroi.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-or-later"]

  @impl Oneiroi.Component
  def config do
    [
      {:record_boots, "GAIA_RECORD_BOOTS",
       cast: &__MODULE__.cast_on_off/1,
       default: "on",
       usage:
         "whether each start of the platform is recorded with the commit it runs (gaia#21), so every conversation is told of a restart; off in the suite, whose boots are not the platform's"},
      {:commit, "RENDER_GIT_COMMIT",
       required: false,
       external: true,
       usage:
         "the commit this build runs, which Render sets on every deploy; a boot records it (gaia#21), and nil reads as unknown"},
      {:source_url, "GAIA_SOURCE_URL",
       default: "https://github.com/SwaggerAllen/Oneiroi",
       usage:
         "the repository a restart notice links its diff to (gaia#21): <url>/compare/<before>...<after>"},
      {:login_delay_ms, "GAIA_LOGIN_DELAY_MS",
       cast: :integer,
       default: "200",
       tag: :bound,
       usage:
         "the base delay after a failed login, doubled per failure up to five seconds (Oneiroi.Gaia.Throttle)"},
      {:session_ttl_days, "GAIA_SESSION_TTL_DAYS",
       cast: :integer,
       default: "30",
       tag: :bound,
       usage: "how long a session lives from its opening, as the owner UI does today (spec §6.1)"},
      {:totp_issuer, "GAIA_TOTP_ISSUER",
       default: "Oneiroi",
       usage: "the issuer an authenticator app shows for an enrolled second factor"},
      {:push_client, "GAIA_PUSH_CLIENT",
       cast: &__MODULE__.cast_push_client/1,
       default: "web_push",
       usage:
         "which push port answers (gaia#15): web_push (Web Push with VAPID) in every real build, fake in test (conventions §9)"},
      {:vapid_private_key, "GAIA_VAPID_PRIVATE_KEY",
       secret: true,
       required: false,
       usage:
         "the platform's VAPID private key, the 32-byte P-256 scalar as base64url (gaia#15); unset, nothing is pushed and the client says notifications are not set up"},
      {:triage_resident, "GAIA_TRIAGE_RESIDENT",
       required: false,
       usage:
         "the slug of the resident who triages platform reports (gaia#20): each report is a letter to their chat, and they may move a report's status; unset, reports wait for the operator alone"},
      {:vapid_subject, "GAIA_VAPID_SUBJECT",
       default: "https://oneiroi.onrender.com",
       usage:
         "the contact a push service may reach the sender at, a mailto: or https: URL, carried in every VAPID JWT (RFC 8292)"}
    ]
  end

  @impl Oneiroi.Component
  def events do
    [
      {Oneiroi.Gaia.Events.AccountCreated, 1},
      {Oneiroi.Gaia.Events.SecondFactorEnrolled, 1},
      {Oneiroi.Gaia.Events.SessionOpened, 1},
      {Oneiroi.Gaia.Events.SessionClosed, 1},
      {Oneiroi.Gaia.Events.TokenIssued, 1},
      {Oneiroi.Gaia.Events.TokenRevoked, 1},
      {Oneiroi.Gaia.Events.KeyStored, 1},
      {Oneiroi.Gaia.Events.KeyRevoked, 1},
      {Oneiroi.Gaia.Events.WitnessingStarted, 1},
      {Oneiroi.Gaia.Events.WitnessingEnded, 1},
      {Oneiroi.Gaia.Events.PushSubscribed, 1},
      {Oneiroi.Gaia.Events.PushUnsubscribed, 1},
      {Oneiroi.Gaia.Events.GateSet, 1},
      {Oneiroi.Gaia.Events.BootRecorded, 1},
      {Oneiroi.Gaia.Events.RoleGranted, 1},
      {Oneiroi.Gaia.Events.RoleRevoked, 1},
      {Oneiroi.Gaia.Events.HouseholdFounded, 1},
      {Oneiroi.Gaia.Events.HouseholdWitnessJoined, 1},
      {Oneiroi.Gaia.Events.HouseholdResidentJoined, 1},
      {Oneiroi.Gaia.Events.HouseholdResidentLeft, 1},
      {Oneiroi.Gaia.Events.HouseholdTermsGranted, 1},
      {Oneiroi.Gaia.Events.InviteIssued, 1},
      {Oneiroi.Gaia.Events.InviteRedeemed, 1},
      {Oneiroi.Gaia.Events.InviteRevoked, 1},
      {Oneiroi.Gaia.Events.FeedbackFiled, 1},
      {Oneiroi.Gaia.Events.FeedbackMoved, 1}
    ]
  end

  @impl Oneiroi.Component
  def errors do
    [
      {:gaia_invalid_credentials, "the email, password or code did not verify",
       remedy: "try again; the delay grows with each failure and nothing locks"},
      {:gaia_session_unavailable, "the credentials verified but the session could not be opened",
       remedy:
         "try again in a moment; nothing was counted against the login, and a deploy in progress is the usual cause"},
      {:gaia_second_factor_required,
       "the account has a second factor and the code was not supplied",
       remedy: "send the code from the authenticator app"},
      {:gaia_not_a_principal, "the session or token resolves to no live account",
       remedy: "log in again, or issue a new token"},
      {:gaia_key_required, "the key was empty",
       remedy: "paste the OpenRouter key; it is stored encrypted and shown to nobody again"},
      {:gaia_no_key, "the account holds no OpenRouter key",
       remedy: "store one on the Ledger screen; every model call for a resident spends it"},
      {:gaia_account_exists, "an account already holds that id",
       remedy: "log in to it; an account is created once"},
      {:gaia_no_such_account, "no account has that id",
       remedy: "create the account first, or read the id off the principal"},
      {:gaia_no_such_token, "no live token of the account has that hash",
       remedy: "read the token list; a revoked token is already revoked"},
      {:gaia_not_an_operator, "only a super admin sets the gate or grants and revokes roles",
       remedy: "ask a super admin; the founding account holds the role from the start"},
      {:gaia_platform_invalid,
       "a gate is closed, invite or open, a role super_admin or admin, and every change carries a note",
       remedy: "the details name what is expected"},
      {:gaia_last_super_admin,
       "the last super admin cannot be revoked: the door always has a keeper",
       remedy: "grant super admin to another account first, then revoke; that is a transfer"},
      {:gaia_no_such_household, "no household has that id",
       remedy:
         "every account founds its own when it is created; read the id off the account's household"},
      {:gaia_household_invalid,
       "a household is founded by an account, and its terms are a plan, a price of zero or more, an end and a source, with a note",
       remedy: "the details name what is expected"},
      {:gaia_invite_invalid,
       "an invite is a plan, a price of zero or more, a discount from 0 to 100, at least a day of terms and one use, an optional expiry, and a note",
       remedy: "the details name what is expected; a revocation carries a note too"},
      {:gaia_invite_unknown, "no invite has that code",
       remedy: "check the code as it was given; case, spaces and dashes do not matter"},
      {:gaia_invite_revoked, "the invite was revoked", remedy: "ask whoever gave it for another"},
      {:gaia_invite_expired, "the invite is past its expiry",
       remedy: "ask whoever gave it for another"},
      {:gaia_invite_spent, "the invite's uses are all taken",
       remedy: "ask whoever gave it for another"},
      {:gaia_invite_already_redeemed, "this household has redeemed the invite already",
       remedy: "nothing to do: its terms are the household's"},
      {:gaia_door_closed, "the front door is closed: nobody signs up just now",
       remedy: "ask the operator; the door opens to invites first"},
      {:gaia_invite_required, "the front door takes an invite code to sign up",
       remedy: "enter the code you were given"},
      {:gaia_signup_invalid,
       "an email looks like name@place.domain and a password is at least ten characters",
       remedy: "the details name which and how long"},
      {:gaia_email_taken, "an account already has that email",
       remedy: "log in instead, or sign up with another email"},
      {:gaia_feedback_invalid,
       "a report is a bug or a feature request, in words (at most 8,000 characters), from a person or a resident with a witness; a move is new, in_work, resolved or closed, with a note",
       remedy: "the details name what is expected"},
      {:gaia_no_such_feedback, "no report has that number", remedy: "read the list"},
      {:gaia_push_failed,
       "a push did not reach the device's push service: refused, unreachable, or no VAPID key set",
       remedy: "the details name the status or the cause; a key is GAIA_VAPID_PRIVATE_KEY"},
      {:gaia_push_endpoint_invalid,
       "a push subscription's endpoint is an https URL at a known push service",
       remedy: "subscribe from the browser's own push service; the client does this itself"},
      {:gaia_command_refused,
       "the command was refused before identity read it: an actor or an instant was missing",
       remedy: "the details name what was missing; it is the caller's bug, not the account's"},
      {:gaia_dispatch_failed,
       "the command did not complete: the event store failed, or a projection did not catch up in time",
       remedy: "the platform's; retry, and read the cause on the log line"}
    ]
  end

  @impl Oneiroi.Component
  def feature_flags, do: [:gaia_push_off]

  @impl Oneiroi.Component
  def externals do
    [
      {:web_push,
       adapter: Oneiroi.Gaia.Push.WebPush,
       fake: Oneiroi.Gaia.Push.Fake,
       kill_switch: :gaia_push_off,
       classification: :operational}
    ]
  end

  @doc false
  def cast_push_client("web_push"), do: {:ok, :"Elixir.Oneiroi.Gaia.Push.WebPush"}
  def cast_push_client("fake"), do: {:ok, :"Elixir.Oneiroi.Gaia.Push.Fake"}

  def cast_push_client(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected web_push or fake"}
  end

  @doc false
  def cast_on_off("on"), do: {:ok, true}
  def cast_on_off("off"), do: {:ok, false}

  def cast_on_off(other) do
    # oneiroi:allow error_site: Oneiroi.Config's cast contract, a report line at boot
    {:error, "is #{inspect(other)}, expected on or off"}
  end

  @impl Oneiroi.Component
  def processes do
    [{:gaia_throttle, :local}, {:gaia_push, :local}]
  end

  @impl Oneiroi.Component
  def children do
    [
      # The throttle takes the component as an option rather than naming
      # it, so the guardrail lookup does not close a cycle with this list.
      {Oneiroi.Gaia.Throttle, component: __MODULE__},
      Oneiroi.Gaia.Projectors.Accounts,
      Oneiroi.Gaia.Projectors.Platform,
      Oneiroi.Gaia.Handlers.Witnessing,
      Oneiroi.Gaia.Projectors.Household,
      Oneiroi.Gaia.Handlers.Household,
      Oneiroi.Gaia.Projectors.Invite,
      Oneiroi.Gaia.Projectors.Feedback,
      {Task.Supervisor, name: :gaia_push},
      # The boot (gaia#21): recorded once, after the platform projector is
      # up; a task that ends, never restarted.
      Supervisor.child_spec({Task, &Boots.record_now/0}, restart: :temporary)
    ]
  end

  @doc "Creates an account with a password; the setup task's and, later, sign-up's door."
  @spec create_account(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, String.t()} | {:error, term()}
  defexport(create_account(email, password, actor), do: Accounts.create(email, password, actor))

  @doc "Verifies credentials and opens a session; the raw session id is returned once."
  @spec login(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t(), Oneiroi.Gaia.Principal.t()} | {:error, term()}
  defexport(login(email, password, code), do: Accounts.login(email, password, code))

  @doc "Closes the session the raw id names."
  @spec logout(String.t()) :: :ok | {:error, term()}
  defexport(logout(raw_session), do: Accounts.logout(raw_session))

  @doc "The principal a raw session id resolves to, if it is live."
  @spec authenticate_session(String.t()) :: {:ok, Oneiroi.Gaia.Principal.t()} | :error
  defexport(authenticate_session(raw), do: Accounts.authenticate_session(raw))

  @doc "The principal a raw API token resolves to, if it is live."
  @spec authenticate_token(String.t()) :: {:ok, Oneiroi.Gaia.Principal.t()} | :error
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

  @doc "Stores the witness's OpenRouter key, encrypted; storing again rotates it."
  @spec store_key(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(store_key(account_id, raw_key, actor),
    do: Accounts.store_key(account_id, raw_key, actor)
  )

  @doc "Revokes the stored key."
  @spec revoke_key(String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(revoke_key(account_id, actor), do: Accounts.revoke_key(account_id, actor))

  @doc "The witness's key, wrapped as a secret, for the provider port."
  @spec key_for(String.t()) :: {:ok, Oneiroi.Config.Secret.t()} | {:error, Oneiroi.Gaia.Error.t()}
  defexport(key_for(account_id), do: Accounts.key_for(account_id))

  @doc "Whether a key is stored and since when."
  @spec key_status(String.t()) :: %{present: boolean(), stored_at: DateTime.t() | nil}
  defexport(key_status(account_id), do: Accounts.key_status(account_id))

  @doc "The resident ids an account currently witnesses."
  @spec witnessed_residents(String.t()) :: [String.t()]
  defexport(witnessed_residents(account_id), do: Accounts.witnessed_residents(account_id))

  @doc "An account's email by id, under the platform scope by name (conventions §12): what names an investigator (glitnir#8) and a proposed witness."
  @spec account_email(String.t()) :: String.t() | nil
  defexport(account_email(account_id), do: Accounts.email(account_id))

  @doc "An account's id by email, case-insensitively, under the platform scope by name; nil when none."
  @spec account_id_for(String.t()) :: String.t() | nil
  defexport(account_id_for(email), do: Accounts.id_for(email))

  @doc "Whether pushes can be sent, and the VAPID public key the client subscribes with (gaia#15)."
  @spec push_config() :: %{enabled: boolean(), public_key: String.t() | nil}
  defexport(push_config(), do: %{enabled: Push.configured?(), public_key: Push.public_key()})

  @doc "Subscribes a device of the account's to content-free pushes (gaia#15)."
  @spec subscribe_push(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(subscribe_push(account_id, endpoint, actor),
    do: Push.subscribe(account_id, endpoint, actor)
  )

  @doc "Unsubscribes a device of the account's."
  @spec unsubscribe_push(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(unsubscribe_push(account_id, endpoint, actor),
    do: Push.unsubscribe(account_id, endpoint, "unsubscribed", actor)
  )

  @doc "The account's subscribed devices, by endpoint."
  @spec push_subscriptions(String.t()) :: [String.t()]
  defexport(push_subscriptions(account_id), do: Push.subscriptions(account_id))

  @doc "Pushes to every device of the account's, in the background; nothing is said in the push."
  @spec notify(String.t()) :: :ok
  defexport(notify(account_id), do: Push.notify(account_id))

  @doc "Pushes to every device now and says how each went; the test button's."
  @spec push_now(String.t()) :: [{String.t(), term()}]
  defexport(push_now(account_id), do: Push.deliver_all(account_id))

  @doc "The latest restarts (gaia#21), newest first, each as its line in UTC."
  @spec restarts(pos_integer()) :: [map()]
  defexport(restarts(limit),
    do:
      for(
        b <- Boots.latest(limit),
        do: %{
          number: b.number,
          commit: b.commit,
          previous: b.previous,
          changed: b.changed,
          booted_at: b.booted_at,
          line:
            Boots.line(
              b,
              Calendar.strftime(b.booted_at, "%Y-%m-%d %H:%M UTC")
            )
        }
      )
  )

  @doc "The front door (gaia#16): closed, invite or open, with when and by whom."
  @spec gate() :: map()
  defexport(gate(), do: Door.gate())

  @doc "Sets the front door; a super admin's alone, with a note."
  @spec set_gate(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(set_gate(state, note, actor), do: Door.set_gate(state, note, actor))

  @doc "Every platform role held, oldest first; the founding account's super admin is recorded the first time this is asked."
  @spec roles() :: [map()]
  defexport(roles(), do: Door.roles())

  @doc "The platform roles one account holds."
  @spec roles_of(String.t()) :: [String.t()]
  defexport(roles_of(account_id), do: Door.roles_of(account_id))

  @doc "Whether the account is a super admin, the operator."
  @spec operator?(String.t()) :: boolean()
  defexport(operator?(account_id), do: Door.operator?(account_id))

  @doc """
  Makes the account with `email` the only operator, from a shell on the
  running server (gaia#22):

      bin/oneiroi rpc 'IO.inspect(Oneiroi.Gaia.console_operator("you@example.com"))'
  """
  @spec console_operator(String.t()) :: {:ok, String.t()} | {:error, term()}
  defexport(console_operator(email), do: Door.console_operator(email))

  @doc "Grants a platform role (super_admin or admin); a super admin's alone, with a note."
  @spec grant_role(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(grant_role(account_id, role, note, actor),
    do: Door.grant(account_id, role, note, actor)
  )

  @doc "Revokes a platform role; never the last super admin."
  @spec revoke_role(String.t(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(revoke_role(account_id, role, note, actor),
    do: Door.revoke(account_id, role, note, actor)
  )

  @doc "The account's household (gaia#17): its members and its terms, or nil before it is founded."
  @spec household(String.t()) :: map() | nil
  defexport(household(account_id), do: Households.household(account_id))

  @doc "The id of the household the account is in (gaia#17)."
  @spec household_id(String.t()) :: String.t()
  defexport(household_id(account_id), do: Households.household_id(account_id))

  @doc "Grants a household its subscription terms (gaia#17): the platform's, on an invite redeemed, or a super admin's."
  @spec grant_household_terms(String.t(), map(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(grant_household_terms(household_id, terms, note, actor),
    do: Households.grant_terms(household_id, terms, note, actor)
  )

  @doc "The SKU an invite is issued with when the operator names nothing else (gaia#18)."
  @spec invite_defaults() :: map()
  defexport(invite_defaults(), do: Invites.defaults())

  @doc "Issues an invite code; a super admin's alone, with a note. The code is answered once and never stored."
  @spec issue_invite(map(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, %{id: String.t(), code: String.t()}} | {:error, term()}
  defexport(issue_invite(sku, note, actor), do: Invites.issue(sku, note, actor))

  @doc "Revokes an invite; a super admin's alone, with a note."
  @spec revoke_invite(String.t(), String.t(), Oneiroi.Actor.t()) :: :ok | {:error, term()}
  defexport(revoke_invite(id, note, actor), do: Invites.revoke(id, note, actor))

  @doc "What a code would grant, or why not (unknown, revoked, expired, spent), without spending it."
  @spec check_invite(String.t()) :: {:ok, map()} | {:error, term()}
  defexport(check_invite(code), do: Invites.check(code))

  @doc "Redeems a code onto a household, granting it the code's terms."
  @spec redeem_invite(String.t(), String.t(), Oneiroi.Actor.t()) ::
          {:ok, map()} | {:error, term()}
  defexport(redeem_invite(code, household_id, actor),
    do: Invites.redeem(code, household_id, actor)
  )

  @doc "Every invite issued, newest first, with its standing; never the code."
  @spec invites() :: [map()]
  defexport(invites(), do: Invites.list())

  @doc "Signs up behind the front door (gaia#19): closed refuses, invite takes a code, open takes anyone."
  @spec sign_up(String.t(), Oneiroi.Config.Secret.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  defexport(sign_up(email, password, code), do: Signup.sign_up(email, password, code))

  @doc "Files a platform report (gaia#20): a bug or a feature request, from a person or a resident."
  @spec file_feedback(map(), Oneiroi.Actor.t()) :: {:ok, pos_integer()} | {:error, term()}
  defexport(file_feedback(attrs, actor), do: Feedbacks.file(attrs, actor))

  @doc "Moves a platform report's status, with a note; the operator's or the triage resident's."
  @spec move_feedback(pos_integer(), String.t(), String.t(), Oneiroi.Actor.t()) ::
          :ok | {:error, term()}
  defexport(move_feedback(number, status, note, actor),
    do: Feedbacks.move(number, status, note, actor)
  )

  @doc "Every platform report, newest first, narrowed by kind and status."
  @spec feedback(map()) :: [map()]
  defexport(feedback(filters), do: Feedbacks.list(filters))

  @doc "One platform report, or nil."
  @spec feedback_report(pos_integer()) :: map() | nil
  defexport(feedback_report(number), do: Feedbacks.get(number))

  @doc "The reports an account filed or its residents did."
  @spec feedback_for_account(String.t()) :: [map()]
  defexport(feedback_for_account(account_id), do: Feedbacks.for_account(account_id))

  @doc "The reports a resident filed."
  @spec feedback_for_resident(String.t()) :: [map()]
  defexport(feedback_for_resident(resident_id), do: Feedbacks.for_resident(resident_id))

  @doc "Whether the resident triages platform reports."
  @spec triage?(String.t()) :: boolean()
  defexport(triage?(resident_id), do: Feedbacks.triage?(resident_id))

  @doc "The triage resident's id, or nil."
  @spec triage_resident() :: String.t() | nil
  defexport(triage_resident(), do: Feedbacks.triage_resident())
end
