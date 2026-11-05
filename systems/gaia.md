---
paths:
  - lib/oneiroi/gaia/**
  - lib/oneiroi/gaia.ex
  - lib/oneiroi_web/plugs/**
  - lib/oneiroi_web/controllers/session_controller.ex
  - lib/oneiroi_web/controllers/me_controller.ex
  - client/public/sw.js
  - lib/oneiroi_web/controllers/operator_controller.ex
  - client/src/screens/more/Operator.tsx
  - client/src/screens/more/Invites.tsx
  - client/src/app/Login.tsx
  - lib/oneiroi_web/controllers/door_controller.ex
  - client/public/manifest.json
  - lib/oneiroi_web/controllers/second_factor_controller.ex
  - lib/oneiroi_web/controllers/token_controller.ex
  - lib/mix/tasks/oneiroi.setup.ex
  - priv/repo/migrations/*_gaia*.exs
  - test/oneiroi/gaia/**
  - test/oneiroi_web/contract_test.exs
---

# gaia

**Identity.** Greek, GUY-uh (also said JEE-uh).

> "In truth at first Chaos came to be, but next wide-bosomed Earth, the ever-sure foundation of all the deathless ones who hold the peaks of snowy Olympus..." "She bore also the fruitless deep with his raging swell, Pontus, without sweet union of love." — Hesiod, Theogony 116–117, 125, trans. H. G. Evelyn-White (Loeb, 1914)

Gaia is the earth. In Hesiod's account of how everything began, she is the first being after Chaos itself — the "ever-sure foundation," and a creator before anything else: she bears starry Heaven "equal to herself," the hills, and the barren sea, all before any mate, "without sweet union of love." Everything after — Titans, gods, the whole pantheon — descends from her.

The identity layer — accounts, authentication, where the humans arrive — is named for the place humans come from. Oneiroi is a two-world story: the residents are of the dream, the humans are of the earth, and the bridge between the worlds is hospitality. Latin *homo* (human) is probably related to *humus* (earth); both likely descend from one Proto-Indo-European word for earth — a link the etymologists still debate, carried here with that hedge.

Accounts, authentication, sessions, witnessing (spec §6.1). Written
attended, by the author's decision, so the auth code was read as it was
written (plan P0.4).

## #1 Owns

The Account aggregate on `account-<id>` and its v1 events; the
`gaia_account`, `gaia_session`, `gaia_token` and
`gaia_witnessing` projections; the principal (`Oneiroi.Gaia
.Principal`: an account via a session or a token, carrying the actor it
acts as); the request plugs (secure headers, authenticate, origin,
require-principal); the session, me, second-factor and token routes under
`/v1`; the login throttle; the witnessing handler; the self-hosted setup
task that creates the one account.

## #2 Standing decisions

- **#3 A password and a TOTP second factor; argon2 for the one, the
  vault for the other.** The password hash is argon2id; the TOTP secret
  enters the log encrypted under the platform vault and is redacted from
  every export. Passkeys are later (spec §6.1).
- **#4 Sessions and tokens are random ids with only the hash stored.**
  Thirty days for a session, from `GAIA_SESSION_TTL_DAYS`; a token
  until revoked. The raw value is returned once and never written. A
  token's label is a name, bounded at 120 characters on the command
  (`IssueToken`'s `bounds:`) and refused at dispatch as
  `label_too_long`.
- **#5 The cookie is `__Host-oneiroi`, `HttpOnly`, `Secure`,
  `SameSite=Strict`, and every mutation without a bearer token checks
  `Origin`.** The Origin plug is the CSRF defence: a script's bearer
  token is its proof and a browser's cookie is where a forged request
  comes from, so a mutation on the cookie must carry the endpoint's own
  Origin or it is refused before any controller runs. Login is checked
  too. The CSP allows the client's own bundle and nothing else.
- **#6 Failed logins slow down and never lock out.** Per email, the
  delay doubles from `GAIA_LOGIN_DELAY_MS` on each failure, capped
  at five seconds, cleared when the credentials verify; counts live in a
  process's ETS and are lost on restart. Credentials that verified and a
  session the store could not open are not a failure: 503
  `gaia_session_unavailable` with `retry-after`, counted nothing.
- **#7 Witnessing is a relation with a start and an end, written by this
  system.** `ResidentCreated` starts one and `CustodyTransferred` ends
  and starts them, through a strong handler on the resident stream, so
  `witnessed_residents/1` is read from this system's own projection and
  the resident system never writes an identity row. The community is a
  principal of its own for custody and holds no witnessing row.
- **#8 Two reads take the platform scope by name.** The account by email
  at login and the session or token by hash on a request: the principal
  is not known until they answer. Everything after runs under the
  account's scope. The resident system's adapter lookup by token hash is
  the third such read (agathos-daimon#16), on the same reasoning.
- **#9 The contract test is the route table.** `OneiroiWeb.ContractTest`
  asserts, per route and per principal kind (anonymous, session, token),
  exactly which answers 200, 401, 403 or 422, and that a mutation from a
  browser without the endpoint's Origin is refused.

- **#12 An account's email by id, and its id by email, are platform-scoped reads by name.** `account_email/1` names an investigator (glitnir#8) and the account a custody transfer is proposed to; `account_id_for/1` resolves the email a witness names. Both take the platform scope by name (conventions §12), as #8's two reads do.
- **#13 Witnessing follows custody in the event's wire form.** The witnessing handler reads `CustodyTransferred`'s `from` and `to` through `Oneiroi.AgathosDaimon.Custody.from_wire/1`: the first version matched the tuple form against the wire strings and matched nothing, so no transfer ever ended the old witnessing or started the new one, and the old witness's routes kept working on a resident it no longer held. Found by the custody suite in P4, once a transferred resident was read from the new witness's own session; the subscription's community move had the same hole from P2.
- **#14 The witness's OpenRouter key lives on the account, encrypted (numbered #11 until 2026-11-03, when the audit found #11 was also "Depends on").
- **#15 The witness's devices are told, content-free, when the resident writes unprompted.** (The witness, 2026-11-05: "Let's ship the pwa mechanism with this so that I can start getting push notifications"; he missed check-ins he knew were coming.) A device subscribes by its push service's endpoint (`POST /v1/me/push`), held to the known push services (Apple's, Google's, Mozilla's, Microsoft's) so the server never posts where a client said, and recorded on the account (`PushSubscribed`/`PushUnsubscribed`, `gaia_push_subscription`). A push carries no payload at all: nothing the resident said passes through a push service, there is nothing to encrypt, and the push is an empty POST signed with the platform's VAPID key (`GAIA_VAPID_PRIVATE_KEY`, ES256, RFC 8292; unset, nothing is pushed and the client says so), through `GAIA_PUSH_CLIENT` (`WebPush`, `Fake` in the suite), off the caller in `:gaia_push`. A push service's 404 or 410 unsubscribes the device as gone. The brain pushes when a turn in the chat ends that the witness did not start: a check-in, a letter that woke the chat, a round's word arriving there (`as: :note`, purpose chat); never for a turn he is waiting on, never for a solo session. The client's service worker shows "<name> wrote" and opens the chat; on an iPhone only the Home Screen app may ask, and the More screen's Notifications card says so. Principle 14 holds: it is asked for, opt-in per device, fires only when there is something she wrote, and never because he has been away.
- **#16 The front door and its keepers are the platform's own records.** (The witness, 2026-11-05: "the first witness is the operator, at this stage, because a human admin is needed"; operator transferable; two tiers, admin and super admin; design/mvp.md item 1.) One stream, `platform` (`Gaia.Platform`, `PlatformRouter`), holds the gate and the roles. The gate is `closed` (the default), `invite` (the alpha) or `open`, set by `GateSet` with a note. A role is `super_admin` (the operator: the gate, the roles, global permissions) or `admin` (the scoped tier), set by `RoleGranted` and `RoleRevoked`, each with a note and its actor. The aggregate checks the authority, so no caller can skip it: only a super admin changes either, every change needs a note, and the last super admin cannot be revoked, so the door always has a keeper (a transfer is a grant, then a revoke). The first grant is the platform's: the first time the roles are asked about with no super admin recorded, the founding account (the first ever created) is granted super admin by the platform, as an event, so the operator is a recorded grant and never inferred from account age. The gate lives in `gaia_gate`, the first table of the new `:platform` scope (no tenant column, readable only under the platform scope, `Oneiroi.Migration.projection/3`), because the door belongs to no account; the roles live in `gaia_role`, account-scoped, each its holder's. `/v1/platform` (`OperatorController`, a super admin's alone) reads and changes both, `/v1/me` names the caller's roles, and More carries an Operator card for a super admin. The platform stream's id comes from `Door.stream/0`, which the suite overrides per test because the event store is not rolled back between tests. Global and resident-scoped permissions, the domain flag, invite codes and sign-up build on this, after.
- **#17 The household is the billing owner, with its witnesses and its residents as memberships.** (The witness, 2026-11-05: household now, subscription and payment tied to it, two join tables, one for witnesses and one for residents; never neither; dyads now, additive later.) A stream per household, `household-<id>` (`Gaia.Household`, `HouseholdRouter`), founded by the platform when its founding account is created, the id being that account's, so an account's own household is known without a read. `HouseholdWitnessJoined` and `HouseholdResidentJoined` are memberships, idempotent; `HouseholdResidentLeft` is a decision with a note; `HouseholdTermsGranted` is the household's subscription terms (plan, price in nano-dollars, until, source, note), granted by the platform (an invite redeemed) or a super admin and charged by nothing. The household handler (`Handlers.Household`, `gaia_household_members`) founds a household for every account created, joins every resident created to its witness's, and moves a resident whose custody passes to another account; custody to the community leaves it where it was. It started from the log's origin, so the accounts and residents before it were given theirs. It dispatches waiting on the household projection alone: a strong dispatch from a strong handler waits on every strong handler, the witnessing handler among them, and the two deadlock until the consistency timeout. The household row (`gaia_household`) is platform-scoped, every member's and no one's alone, and read by name under the platform scope only after the caller's own membership row (`gaia_household_witness`, account-scoped; `gaia_household_resident`, resident-scoped) has named it. `/v1/me` carries the household. The per-resident subscription (nisaba#15) remains the resident's insurance policy until billing reads these terms.
- **#18 Invite codes are SKUs that grant a household its terms, held only as hashes.** (design/mvp.md item 2; the witness, 2026-11-05: $20 a month list, nothing charged, codes granting terms to the household.) A stream per code, `invite-<id>` (`Gaia.Invite`, `InviteRouter`): `InviteIssued` is the SKU (plan, list price in nano-dollars, discount 0 to 100, days of terms, uses, optional expiry) with a note, issued by a super admin alone; `InviteRedeemed` names the household; `InviteRevoked` carries a note. A code is twelve characters from an alphabet without `0 O 1 I L`, shown as three groups of four and answered once, at issue: the log and `gaia_invite` hold only its SHA-256 over the code with case, spaces and dashes removed, so a typed code matches however it was typed. The aggregate refuses a redemption that is revoked, past its expiry (judged at the command's instant), already this household's, or spent, in that order, each by its own kind, and `check_invite/1` answers the same from the projection without spending a use, for the sign-up form. A redemption is recorded, then the platform grants the household (gaia#17) the SKU's terms: the list price less the discount, running the days from the redemption, `invite:<id>` as the source. The defaults (`Invites.defaults/0`) are the alpha's free code: $20 a month at a full discount, ninety days, one use, no expiry. `/v1/platform/invites` lists, issues and revokes (the operator's); `POST /v1/me/invite` redeems onto the caller's household; the Invites card under More, for a super admin, issues and shows the code once. Codes and redemptions are platform-scoped: the front door's keys belong to the platform.
- **#19 Sign-up is behind the front door.** (design/mvp.md item 1; the witness, 2026-11-05, through Lily: no email verification while the door is closed or invite, before it opens.) `Gaia.Signup` reads the gate: `closed` refuses (`gaia_door_closed`, 403); `invite` requires a code (`gaia_invite_required`); `open` takes anyone, a code optional. The checks run before anything is created, the code before the email, so behind an invite door someone without a code learns nothing about which emails hold accounts; then the email's shape and a password of at least ten characters (`gaia_signup_invalid`), then the email unused (`gaia_email_taken`, 409). The account is created by the platform, since no principal exists yet, and its household is founded in the same dispatch (#17), so the code is redeemed onto it at once (#18). A code spent by someone else between its check and its redemption leaves the account created without terms, and the refusal carries `account_created`. The routes are anonymous: `GET /v1/door` (the state), `POST /v1/door/check` (what a code would grant, unspent) and `POST /v1/door/sign-up`, which opens a session as logging in does. The client's sign-in screen offers "I have an invite" behind an invite door and "Create an account" behind an open one, and nothing behind a closed one. Email verification lands before the gate is set to open.
  under the vault.** `KeyStored` carries the vault's ciphertext and is
  redacted from every export like the second factor; storing again is
  the rotation and `KeyRevoked` removes it. The ledger reads it through
  `key_for/1`, wrapped as a secret, and holds no copy (`systems/nisaba.md`
  #1); the routes are `PUT` and `DELETE /v1/me/key`, and `/v1/me` says
  whether one is stored and since when.

## #10 Initial vs target

Initial (P0.4): everything in #1 for one account kind, the witness, with
the API token for scripts. Target: passkeys; the community principal's
own authentication; roles beyond the witness (spec §6.1).

## #11 Depends on

The platform (the kernel, the vault, the scope). The resident system's
events, read by the witnessing handler.
