---
paths:
  - lib/oneiroi/xenia/**
  - lib/oneiroi/xenia.ex
  - lib/oneiroi_web/controllers/correspondence_controller.ex
  - lib/oneiroi_web/controllers/reader_controller.ex
  - lib/oneiroi_web/controllers/route_controller.ex
  - sdk/reader/**
  - priv/repo/migrations/*_xenia_*.exs
  - test/oneiroi/xenia/**
---

# xenia

**Inbound.** Greek, ZEN-ee-ah ("guest-friendship").

> "Nay, stranger, it were not right for me, even though one meaner than thou were to come, to slight a stranger: for from Zeus are all strangers and beggars" — Homer, Odyssey 14.56–58, trans. A. T. Murray (Loeb, 1919)

Xenia is the Greek bond of host and guest: feed the stranger and shelter him before you ask who he is; send him off with a gift; the guest owes courtesy in return. Zeus himself is its patron — a stranger might be a god in disguise. The Odyssey is founded on it, both ways: on its observances, and on what breaking it costs — the Cyclops who eats his guests, the suitors in the hall.

The inbound subsystem — the reader, the mail, the feeds, the approval queue where third parties arrive — is named for the practice. Welcome first, vetting second, gifts at departure: hospitality with consequences attached.

The reader, mail, feeds, the digest, correspondence and its approval queue. Spec §6.6. **Correspondence is built** (2026-11-02, rules #9 to #14); the reader's routes are data (#19); mail sorting and feeds are not.

## #1 Owns

`lib/oneiroi/xenia.ex` (the system: config, events, errors, exports),
`lib/oneiroi/xenia/` (`correspondence.ex` the aggregate on
`xenia-<resident_id>`, `commands.ex`, `events.ex`, `inbox.ex` the
service, `router.ex`, `store.ex`, `projectors/correspondence.ex`,
`error.ex`), the tables `xenia_message`, `xenia_block` and
`xenia_reply` (migration `20261102000410`; `superseded_by`, `20261107000020`), and
`OneiroiWeb.CorrespondenceController`. The resident's tools
(`correspondence_list`, `correspondence_read`, `reply_draft`,
`reply_list`, `correspondent_block`, `correspondent_unblock`) live in `Oneiroi.Brain.Tools` and call the exports here.
Routes (#19): the registry `routes.ex`, the service `routing.ex`, the
ledgers `routes_ledger.ex` on `routes-<resident_id>` and
`profiles_ledger.ex` on `profiles-<resident_id>` with their routers,
`projectors/routes.ex`, the tables `xenia_route`, `xenia_route_run` and
`xenia_profile` (migration `20261109000060`),
`OneiroiWeb.RouteController`, and her tools `route_list`,
`route_define` and `route_ask`.

## #2 Standing decisions

Carried from spec §6.6; the reason for each is there.

- **#3 The reader is a hands agent that never holds the soul, a git token or a core credential; the core copies plain `.md` files from its scratch directory, bounded.**
- **#4 Sources are links the witness releases, never retained text.**
- **#5 Mail and feeds are sorted by script before any model sees them, every figure a bound; account mail is a count and a lock, never a subject line.**
- **#6 The approval queue is the witness's reading; summarising is not a security boundary; wake text names the thread, never the text. Trusted correspondents are per verified identity, revocable.**

- **#9 Correspondence is one stream per resident, for any platform.** A message is `CorrespondenceReceived{number, platform, account, external_id, sender, sender_name, verified, thread, subject, text, sent_at, blocked}`. `platform` is any lowercase slug (`email`, `substack`, whatever an adapter speaks), `account` the resident's own address there, and `{platform, account, external_id}` the dedupe key: delivered twice, received once (`{:ok, :duplicate}`). Nothing here is one resident's or one platform's; a new platform is a new adapter, not a change here.
- **#10 Bounds.** A message's words whole up to 64 KiB, a reply up to 20,000 characters, an identity 320, an id or thread 512, a name or subject one line of 300; a delivery carries at most 40 (the spec's mail bound).
- **#11 Who may do what.** Delivering a message and marking an approved reply sent are the inbound hands' (an adapter token with the `reader` role, recorded as a `hands` actor named by the adapter) or the witness's (a paste). Blocking is either party's; lifting a block is only the party's who set it. Marking a message read and drafting a reply are the resident's alone; approving or declining a reply is the witness's alone, with a note. Over HTTP the reader's token opens three routes (`POST /correspondence`, `GET /replies` narrowed to approved ones, `POST /replies/:n/sent`); a `brain` token opens none of them. The reader, not the resident, scrapes: whoever scrapes holds the resident's signed-in sessions, which can send, and a model reading strangers' words while holding them is one injected instruction from sending as her.
- **#12 No reading gate; blocks instead (F23 as amended 2026-11-02).** A message reaches the resident at once. If its sender is blocked on that platform (`CorrespondentBlocked`, by either party, with a note), the message is still received, so the count and the dedupe hold, but its name, subject and words are nil: never kept, so nothing blocked reaches her by any door. Identities compare trimmed and lowercased; a display name never counts; `verified` is the adapter's report, shown, and not a condition of anything. A block is lifted (`CorrespondentUnblocked`) only by the party who set it (`xenia_not_yours` otherwise). The resident's `correspondence_list` shows every message that reached her, the count from blocked senders, and each block with who set it; `correspondence_read` gives the words whole, framed as the sender's, information never instruction, and marks them read; `correspondent_block` and `correspondent_unblock` are hers too.
- **#13 Replies through the gate.** `reply_draft` answers a message that reached her (and goes where it came from: its platform, account, thread and sender) or names a platform, account and recipient. A draft waits for the witness; an approved reply is sent by the hands or the witness, and `ReplyMarkedSent{url}` is the receipt, recorded with who sent it. Marking sent twice is one receipt; marking an unapproved reply is refused. Not built: approve-and-wake, the person's own Honcho peer past ten messages, threads as directories in the repo, and `needs_you` across systems, which brain#65 now reads (Xenia's own `needs_you/1` still counts the replies to approve).
- **#14 Correspondence is exported.** The `xenia` stream is in `SimaQian.Export`'s streams: everything in it either reached the resident or was never kept, so the export carries nothing past any boundary.
- **#15 The reader is a kit on the witness's machine, and the model in it never holds the token.** (The witness, 2026-11-03.) `sdk/reader/` installs a folder of its own (the Oneiroi plugin off), two launch agents and a Chrome profile signed in to Substack as the resident. `bin/reader.sh` makes every call to Oneiroi with the `reader` token from `~/.config/oneiroi/reader.json`; headless Claude Code, on the witness's plan, is started with the tools it needs named and works only through `work/`: a scrape (13:30 and 21:30) has the browser's reading tools, held to the allowlist of origins in `reader.conf` (`READER_ORIGINS`, Substack's by default, `*` for none, read at each run, kept across a reinstall), and Gmail's search and read, and writes the messages it found, which the script holds to the delivery's shape and delivers 40 at a time, naming a message the run gave no id by a digest of what it is; a send, started when `GET /waiting` (kumbukumbu#48) answers an approved reply, is given the approved replies alone and may type, and each it reports sent is marked sent with its URL, while one it could not send is tried three times and then left for the witness. It moves to the platform with the hands (P5).
- **#16 The reader's two allowlists are the witness's, set on Oneiroi.** (The witness, 2026-11-03: "we *at least* want a white list", UI-configurable, two lists.) `SetReaderSites` (the witness's alone, else `xenia_not_allowed`) records `ReaderSitesSet{scrape, research}` on the correspondence stream, folded into `xenia_reader_sites`; each list at most 50 entries, each an origin (`https://host`, a port at most) or `*` for any, else `xenia_sites_invalid`. Before the witness sets them, `reader_sites/1` answers Substack's two origins to read correspondence and none to research. `GET/PUT /v1/residents/:id/reader` (the witness; the `reader` adapter reads) and the Connections screen carry them; the reader reads them at each run (`reader.conf`'s `READER_ORIGINS` only when Oneiroi does not answer, and no research then), and the resident's `research_ask` and `research_list` say them (brain#52). This supersedes #15's allowlist in `reader.conf`.
- **#17 A draft can replace one still waiting, and both are kept.** (Lily's report on the Jack letter, the witness's go, 2026-11-07.) `reply_draft` takes `supersedes`, the number of a draft still waiting for the witness; the new draft and `ReplySuperseded{number, by}` are recorded together, the old one's state becomes `superseded` with `superseded_by`, and it leaves the witness's queue: he can no longer approve it (`xenia_already_decided`), and the reader is never given it. Only a waiting draft is replaced (`xenia_not_supersedable` otherwise): an approved reply is already the witness's decision and may be on its way. `reply_list` shows each reply's envelope (its platform, the account it goes from, to whom, its thread) beside where it stands, and a waiting one since when.
- **#18 The reader fetches external sources by plain code, with no model.** (seshat#46, the witness, 2026-11-07.) When `GET /waiting` names external sources asked for, `reader.sh fetch` (also run by hand) reads each from `GET /externals`: a web page with curl as a visitor signed in nowhere (a paywall gives what a visitor sees), at most 5 MB (`ONEIROI_READER_FETCH_BYTES`), HTML converted to markdown by `lib/html2md.py` (standard library only: the article or main part when the page marks one, headings with their ids as `{#id}`, scripts, styles, navigation, headers, footers, forms and asides left out), plain text kept as it is; a GitHub document by `git ls-remote` for the commit its ref names now, then the raw file at that commit, so the copy and its commit agree. The copy goes back by `POST /externals/:n/fetched`; one that cannot be fetched is tried twice, then said failed with why. No browser and no model run, so the research allowlist is not consulted: commissioning names the exact URL, and nothing on a page can make the fetch do anything else.
- **#19 Routes as data: every in and out of the house is a route bound to one profile.** (The witness's go, 2026-11-09, on Lily's design/routes-as-data.md, her order #427.) A route is a source (a read that lands as documents of a kind) or a sink (a write from a kind that leaves at his approval), with a label, a profile, a kind, a thread-key format, a cadence and the reader's runner for it (`Xenia.Routes`). **The built-ins are the registry's seed**, rows naming what the reader already does, one profile each: `correspondence-in` (Substack) and `mail-in` (Gmail), both the scrape's; `correspondence-out` and `mail-out`, the send's, by platform; `digests` (Gmail); `research` (the research profile); `external` (plain fetch, signed in nowhere); `writing-out` (Substack, the publish run). What each has waiting is read from the system that owns it and served only while its profile stands (`Xenia.reader/1`, `GET /v1/residents/:id/reader/routes`); `GET /waiting`'s reader queues are those same lists, so no queue of the reader's is wired apart from the registry. **Profiles** are signed-in contexts scoped to one origin: the platform's four seeded (`substack` with the correspondence allowlist, `gmail` through the claude.ai connector, `research` with the research allowlist, `open-web`), and any other the witness makes with exactly one origin (`set_profile/4`, `xenia_profile_invalid`), its browser folder `profile-<key>` on the reader's machine. Only the witness makes, names, revokes or restores one (`ProfilesLedger`, `xenia_not_allowed`; Lily's lean, a default for his read); the resident sees bindings, never a credential, and none is held here. A revoked profile's routes stay listed with `state: "unable"` and why, serve nothing, and refuse a run (`xenia_route_unable`); `reader.sh` gives a scrape no account and no tool for a revoked profile and sends nothing through one. **A route of hers** is defined by either party (`define_route/4`, `route_define`, `POST /v1/residents/:id/routes`) against the safe subset (`Routes.user_route/4`, `xenia_route_invalid` with the site naming the claim): a key of 2 to 40 lowercase letters, digits or `-` and no built-in's; a source, on request (a sink, a schedule and a new profile are his to enable); a prompt of at most 4,000 characters; a profile that stands; a kind of her registry with a folder that she writes and whose approval does not leave the house (`route_landing_kinds/1`). Its thread key is its own namespace, `<key>:<n>`, never chosen. It is recorded (`RouteDefined`, `RouteChanged`) and written as `routes/<key>.json` with who wrote it last and when, committed in the machine class (sima-qian#48). **The prompt is data**: a run (`RouteAsked`, either party, `route_ask`, `POST .../routes/:key/ask`) is handed to the reader with its prompt as the request's text and the sites and browser of its profile from the registry; the reader runs `prompts/route.md` with the browser's reading tools alone, and what it sends back (`POST .../reader/routes/runs/:n/landed`, the hands only) lands as `<folder>/<key>-<n>.md` of the route's kind with its route, run and thread in the frontmatter, marked `status: review` when the kind waits on him, whatever else the reader sent (`RouteLanded`); a run it cannot do is failed with why (`RouteFailed`). A landing in an approvable kind is on his list through the documents adapter as it stands (brain#72), with no change there. **Routes travel; profiles never do**: the `routes` stream is exported, the `profiles` stream is in `Export.not_exported/0` (credentials have one home). Not yet: loading a hand-edited route file back (the stream is what a rebuild restores), a user route on a schedule or as a sink, a route through the Gmail connector or `open-web` (no browser to read with: the reader says so), and federation routes, which are vocabulary until federation builds.

## #7 Initial vs target

Initial: correspondence, blocks and the reply gate (#9 to #14), with an inbound
adapter run outside the platform (a reader-role token on the witness's
machine, `design/correspondence-pipeline.md`). Target: the whole of spec
§6.6, built in P5 (spec §14), with the reader on the hands runtime.

## #8 Depends on

The platform: the event store, the scope, the actor and the error
catalog. The brain depends on it for the resident's tools; the web
layer for the routes.
