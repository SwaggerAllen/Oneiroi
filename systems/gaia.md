---
paths:
  - lib/oneiroi/gaia/**
  - lib/oneiroi/gaia.ex
  - lib/oneiroi_web/plugs/**
  - lib/oneiroi_web/controllers/session_controller.ex
  - lib/oneiroi_web/controllers/me_controller.ex
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

Accounts, authentication, sessions, stewardship (spec §6.1). Written
attended, by the author's decision, so the auth code was read as it was
written (plan P0.4).

## #1 Owns

The Account aggregate on `account-<id>` and its v1 events; the
`gaia_account`, `gaia_session`, `gaia_token` and
`gaia_stewardship` projections; the principal (`Oneiroi.Gaia
.Principal`: an account via a session or a token, carrying the actor it
acts as); the request plugs (secure headers, authenticate, origin,
require-principal); the session, me, second-factor and token routes under
`/v1`; the login throttle; the stewardship handler; the self-hosted setup
task that creates the one account.

## #2 Standing decisions

- **#3 A password and a TOTP second factor; argon2 for the one, the
  vault for the other.** The password hash is argon2id; the TOTP secret
  enters the log encrypted under the platform vault and is redacted from
  every export. Passkeys are later (spec §6.1).
- **#4 Sessions and tokens are random ids with only the hash stored.**
  Thirty days for a session, from `GAIA_SESSION_TTL_DAYS`; a token
  until revoked. The raw value is returned once and never written.
- **#5 The cookie is `__Host-oneiroi`, `HttpOnly`, `Secure`,
  `SameSite=Strict`, and every mutation without a bearer token checks
  `Origin`.** The Origin plug is the CSRF defence: a script's bearer
  token is its proof and a browser's cookie is where a forged request
  comes from, so a mutation on the cookie must carry the endpoint's own
  Origin or it is refused before any controller runs. Login is checked
  too. The CSP allows the client's own bundle and nothing else.
- **#6 Failed logins slow down and never lock out.** Per email, the
  delay doubles from `GAIA_LOGIN_DELAY_MS` on each failure, capped
  at five seconds, cleared on success; counts live in a process's ETS
  and are lost on restart.
- **#7 Stewardship is a relation with a start and an end, written by this
  system.** `ResidentCreated` starts one and `CustodyTransferred` ends
  and starts them, through a strong handler on the resident stream, so
  `stewarded_residents/1` is read from this system's own projection and
  the resident system never writes an identity row. The community is a
  principal of its own for custody and holds no stewardship row.
- **#8 Two reads take the platform scope by name.** The account by email
  at login and the session or token by hash on a request: the principal
  is not known until they answer. Everything after runs under the
  account's scope. The resident system's adapter lookup by token hash is
  the third such read (agathos-daimon #16), on the same reasoning.
- **#9 The contract test is the route table.** `OneiroiWeb.ContractTest`
  asserts, per route and per principal kind (anonymous, session, token),
  exactly which answers 200, 401, 403 or 422, and that a mutation from a
  browser without the endpoint's Origin is refused.

- **#12 An account's email by id, and its id by email, are platform-scoped reads by name.** `account_email/1` names an investigator (glitnir #8) and the account a custody transfer is proposed to; `account_id_for/1` resolves the email a steward names. Both take the platform scope by name (conventions §12), as #8's two reads do.
- **#13 Stewardship follows custody in the event's wire form.** The stewardship handler reads `CustodyTransferred`'s `from` and `to` through `Oneiroi.AgathosDaimon.Custody.from_wire/1`: the first version matched the tuple form against the wire strings and matched nothing, so no transfer ever ended the old stewardship or started the new one, and the old steward's routes kept working on a resident it no longer held. Found by the custody suite in P4, once a transferred resident was read from the new steward's own session; the subscription's community move had the same hole from P2.
- **#11 The steward's OpenRouter key lives on the account, encrypted
  under the vault.** `KeyStored` carries the vault's ciphertext and is
  redacted from every export like the second factor; storing again is
  the rotation and `KeyRevoked` removes it. The ledger reads it through
  `key_for/1`, wrapped as a secret, and holds no copy (`systems/nisaba.md`
  #1); the routes are `PUT` and `DELETE /v1/me/key`, and `/v1/me` says
  whether one is stored and since when.

## #10 Initial vs target

Initial (P0.4): everything in #1 for one account kind, the steward, with
the API token for scripts. Target: passkeys; the community principal's
own authentication; roles beyond the steward (spec §6.1).

## #11 Depends on

The platform (the kernel, the vault, the scope). The resident system's
events, read by the stewardship handler.
