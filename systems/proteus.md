---
paths:
  - lib/oneiroi/proteus/**
  - lib/oneiroi/proteus.ex
  - lib/oneiroi_web/controllers/honcho_controller.ex
  - priv/templates/honcho-custom-instructions.md
  - priv/repo/migrations/*_proteus.exs
  - test/oneiroi/proteus/**
---

# proteus

**The bridge to Honcho.** Greek, PROH-tee-us.

> "immortal Proteus of Egypt, who knows the depths of every sea, and is the servant of Poseidon." "For try he will, and will assume all manner of shapes of all things that move upon the earth, and of water, and of wondrous blazing fire" — Homer, Odyssey 4.385–386 and 417–418, trans. A. T. Murray (Loeb, 1919)

Proteus is the Old Man of the Sea. He knows everything, and he will say it only to someone who holds on through every shape he takes: Menelaus, told the trick by Proteus's own daughter Eidothea, grips him through lion, serpent, leopard, boar, water and tree until he gives up the changing and speaks true.

The bridge to Honcho, which keeps a model of each person in the conversation (the peer cards, the custom instructions, the card audit), is named for the shape-changer. A model of a person is a thing that keeps changing shape, and it answers truly only to the one who holds on through the changes. The name takes the knowledge and the grip.

The bridge, workspaces, peer cards, custom instructions, the card audit.
Spec §6.9. Built (P2, slice 3) under `Oneiroi.Proteus`, the system's
name, where the spec's file map said `honcho/`. The weekly memory audit
that reads through it is judgement's (eunomia #22).

## #1 Owns

The bridge aggregate on `honcho-<resident_id>` (`Bridge`, `Commands`,
`Events`, `Router`) with `WorkspaceProvisioned`, `PeerAdded`, `CardSet`,
`CardAudited`, `CardAuditFailed`, `TurnSynced`, `SyncFailed` and
`KeyMinted`; the `proteus_bridge` and `proteus_sync` projections; the
read of Honcho's memory of the resident for the records export
(`memory/1`, #18); the port (`Honcho`) with Honcho's HTTP API behind it (`Honcho.HTTP`) and the
in-memory Honcho (`Honcho.Fake`); the service (`Bridges`); the weekly
card audit (`CardAuditWorker`); the honcho route under
`/v1/residents/:id`. The custom-instructions template is the resident
system's to render (agathos-daimon #19) and the records export's to
write (sima-qian #13).

## #2 Standing decisions

Carried from spec §6.9; the reason for each is there.

- **#3 One workspace per resident; each hands runtime gets a workspace-scoped, expiring key, and the admin key never leaves the core.**
- **#4 Reads of Honcho's tables go through one module tested against Honcho's own DDL; writes go through its API; every query filters by workspace and a test seeds two and asserts no bleed.**
- **#5 The card comes from git, always; correspondence is not sent to Honcho.**

Decided in the build:

- **#8 Everything goes through the port, and the workspace is the resident's id.** `Oneiroi.Proteus.Honcho` is the one shape: workspace, peers, sessions, messages, the card, the context, the conclusions, keys. The implementation is named in `PROTEUS_CLIENT` (honcho, the HTTP API, in every real build; fake in the suite), registered in `externals/0` with the `proteus_honcho_off` kill switch, classified personal. Every call takes the workspace first, so there is no call that reaches Honcho without one.
- **#9 The HTTP shapes are claims until the pinned image answers them.** The paths are read from v3.2.2's routers (workspaces, peers, sessions, messages, conclusions, keys under `/v3`, the admin key as a bearer); the bodies (`name`, `peer_names`, `messages[].peer_name`, `peer_card`, `configuration`, `filters.observer`/`observed`) are what the routers read and the docs describe, not what a recorded fixture shows, and `Honcho.HTTP` says so. The integration layer against the pinned image is the measurement (conventions §9).
- **#10 Reads of Honcho's tables wait on the image.** Until the compose stack carries it, the bridge reads through the API as well (the context, the conclusions, the card); the plain-SQL module the spec allows, tested against the dumped DDL, is built then and nowhere before.
- **#11 The weekly card audit is a cross-tenant job under the platform scope, named here.** Sunday 03:00 UTC, before judgement's memory audit; the roster is the resident system's platform-scoped export, and only residents with a workspace are visited.
- **#12 Provisioning is the first captured turn's, and the card is set from git on it.** `sync_turn/5` provisions on first contact with Honcho: the workspace, `resident-<id>` and `witness-<account_id>` with the rendered custom instructions as each peer's configuration, then the card. A witness the workspace has not met (a second account party to a session) is added as a peer when its words arrive.
- **#13 A turn syncs once, as the two peers' words, and a failure is the bridge's.** User messages by a witness go as the witness's peer and assistant messages as the resident's; system and tool messages do not go. The sync row for the turn is read before anything is sent, because the aggregate's once-a-turn answer comes after the send: the first version sent a retried turn twice and recorded it once, and the test that counts Honcho's messages found it. A Honcho that is down is `SyncFailed` on the stream and a failed sync row, returned and never raised; the brain goes on. A retried turn after a failure lands as one row, synced.
- **#14 The card is the soul's paragraphs, hashed, and a dream that moved it is pinned back.** `card/1` is `SOUL.md` and `IDENTITY.md` as written, one line per paragraph with headings dropped (a heading names a file, not the resident) and the soul lines' markers stripped (a number is for citing, not for the peer to read; agathos-daimon #27), each cut at 300 characters. `set_card/3` writes it and records `CardSet` with the hash and the source (provision, commit, audit); the same hash is no event unless the audit set it. `audit_card/2` reads Honcho's card and, if it differs, sets git's again and records `CardAudited{moved, repinned}`.
- **#15 Honcho's context is a section of the brain's turn, bounded.** `context/1` reads the resident's view of the witness within `PROTEUS_CONTEXT_TOKENS` (800, a guess at the prefix's share); the brain injects it as `honcho` (brain #19). Empty when there is no workspace or Honcho is down, so a turn never waits on it.
- **#16 Render's blueprint wires Honcho with nothing typed but the provider key.** `PROTEUS_HONCHO_URL` takes an http(s) URL or the bare `host:port` Render's `fromService` hands over for a private service, read as http, with the port explicit (a bare host is refused rather than sent to port 80). With `PROTEUS_HONCHO_ADMIN_KEY` unset, the core mints the admin JWT from `PROTEUS_HONCHO_JWT_SECRET`, Honcho's own `AUTH_JWT_SECRET`, exactly as Honcho's `create_admin_jwt` does: HS256 over `{"t": "", "ad": true}`. The blueprint generates the secret on `honcho-api` and copies it here, so each environment, previews included, holds its own; an admin key set by hand still wins.
- **#17 Honcho shares Oneiroi's database, in its own schema under its own role.** A migration creates `oneiroi_honcho` (no login, no bypass of row-level security), the `honcho` schema it owns, and CREATE on the database, which Honcho's startup `CREATE SCHEMA IF NOT EXISTS` needs even when the schema exists. render.yaml hands both Honcho services Oneiroi's connection string, rewritten to Honcho's `postgresql+psycopg://` scheme with a startup option that takes the role (`options=-c role=oneiroi_honcho`), `DB_SCHEMA=honcho`, and a pool of three each with no overflow. Measured locally with async SQLAlchemy over psycopg on the exact URL: the connection is the role, Honcho's startup statements pass, a vector column is made in its schema, and reading an Oneiroi table or creating one in `public` is refused. A wall against accident and not against Honcho: the login is Oneiroi's credential, so `SET ROLE` back to it succeeds (also measured). Honcho's own migrations do not take the role: its Alembic passes `connect_args={"options": ...}`, which replaces the URL's, so its tables are the login's, and the first live deploy's app was refused them. A second migration grants the role everything in `honcho` and, by default, whatever the login makes there later: the migrator owns, the application role is granted, as in Oneiroi itself. `honcho-api` runs the two lines of Honcho's entrypoint itself with `--port "$PORT"` and `PORT=10000`, because Render kept the service's address at 10000 after its server moved to 8000. Every Honcho feature runs on OpenRouter through its openai transport with the one key, on Honcho v3.2.2's default models under their OpenRouter names and the embedding model Seshat pins.

- **#18 Honcho's memory of the resident is read whole for the records export, in the shapes of the client released for v3.2.2.** `memory/1` (`Bridges.memory/2`) reads the provisioned workspace through the port: every peer (`POST /v3/workspaces/{ws}/peers/list`), every card each peer holds of itself and of each other peer (`GET .../peers/{observer}/card`, with `?target=` for another), every conclusion (`POST .../conclusions/list`, no filter, with its observer and observed, session, level, sources and instant), and every session's summaries (`POST .../sessions/list`, then `GET .../sessions/{id}/summaries`). Every list is walked page by page at 100 a page from page 1 to the `pages` the answer counts. Nil before provisioning; one failed read fails the whole, so a part is never taken for it. The paths, the bodies and the answers are read from honcho-ai 2.5.1, the Python SDK Honcho's compatibility guide pairs with v3.2.2 (its `routes`, its calls and the pydantic models it validates with), and a test at the HTTP boundary holds `Honcho.HTTP` to them against a Honcho on the loopback answering those shapes; they stay claims until the pinned image answers (#9). Not read, because Honcho does not hold them alone: its copies of the turns, the peers' and sessions' configuration, the representation and context it assembles per query, and its queue. The export is the records system's to write (sima-qian #42). The same reading found that 2.5.1 sends `id` where the writes above send `name`, `peer_id` where they send `peer_name`, and filters conclusions by `observer_id`/`observed_id` where `conclusions/4` sends `observer`/`observed`; whether v3.2.2 takes the older names is not measured.

## #6 Initial vs target

Initial (P2, slice 3): #8 to #15 over the HTTP port as claims and the
in-memory Honcho as the suite's. Target: the table reads against the
pinned image's DDL (#10), the recorded fixtures that confirm the HTTP
shapes (#9), a person's own peer past the threshold and the witness's
promotion with inbound (spec §6.9), the hands key on wake (P3).

## #7 Depends on

The resident system for the row, the identity context, the custom
instructions and the active roster; nothing else of the core. The
brain, the records backup and judgement depend on this system, and it
reaches none of them.
