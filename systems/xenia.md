---
paths:
  - lib/oneiroi/xenia/**
  - lib/oneiroi/xenia.ex
  - lib/oneiroi_web/controllers/correspondence_controller.ex
---

# xenia

**Inbound.** Greek, ZEN-ee-ah ("guest-friendship").

> "Nay, stranger, it were not right for me, even though one meaner than thou were to come, to slight a stranger: for from Zeus are all strangers and beggars" — Homer, Odyssey 14.56–58, trans. A. T. Murray (Loeb, 1919)

Xenia is the Greek bond of host and guest: feed the stranger and shelter him before you ask who he is; send him off with a gift; the guest owes courtesy in return. Zeus himself is its patron — a stranger might be a god in disguise. The Odyssey is founded on it, both ways: on its observances, and on what breaking it costs — the Cyclops who eats his guests, the suitors in the hall.

The inbound subsystem — the reader, the mail, the feeds, the approval queue where third parties arrive — is named for the practice. Welcome first, vetting second, gifts at departure: hospitality with consequences attached.

The reader, mail, feeds, the digest, correspondence and its approval queue. Spec §6.6. **Correspondence is built** (2026-11-02, rules #9 to #13); the reader, mail sorting, feeds and the digest are not.

## #1 Owns

`lib/oneiroi/xenia.ex` (the system: config, events, errors, exports),
`lib/oneiroi/xenia/` (`correspondence.ex` the aggregate on
`xenia-<resident_id>`, `commands.ex`, `events.ex`, `inbox.ex` the
service, `router.ex`, `store.ex`, `projectors/correspondence.ex`,
`error.ex`), the tables `xenia_message`, `xenia_correspondent` and
`xenia_reply` (migration `20261102000410`), and
`OneiroiWeb.CorrespondenceController`. The resident's tools
(`correspondence_list`, `correspondence_read`, `reply_draft`,
`reply_list`) live in `Oneiroi.Brain.Tools` and call the exports here.

## #2 Standing decisions

Carried from spec §6.6; the reason for each is there.

- **#3 The reader is a hands agent that never holds the soul, a git token or a core credential; the core copies plain `.md` files from its scratch directory, bounded.**
- **#4 Sources are links the witness releases, never retained text.**
- **#5 Mail and feeds are sorted by script before any model sees them, every figure a bound; account mail is a count and a lock, never a subject line.**
- **#6 The approval queue is the witness's reading; summarising is not a security boundary; wake text names the thread, never the text. Trusted correspondents are per verified identity, revocable.**

## Built rules

- **#9 Correspondence is one stream per resident, for any platform.** A message is `CorrespondenceReceived{number, platform, account, external_id, sender, sender_name, verified, thread, subject, text, sent_at, trusted}`. `platform` is any lowercase slug (`email`, `substack`, whatever an adapter speaks), `account` the resident's own address there, and `{platform, account, external_id}` the dedupe key: delivered twice, received once (`{:ok, :duplicate}`). Nothing here is one resident's or one platform's; a new platform is a new adapter, not a change here.
- **#10 Bounds.** A message's words whole up to 64 KiB, a reply up to 20,000 characters, an identity 320, an id or thread 512, a name or subject one line of 300; a delivery carries at most 40 (the spec's mail bound).
- **#11 Who may do what.** Delivering a message and marking an approved reply sent are the inbound hands' (an adapter token with the `reader` role, recorded as a `hands` actor named by the adapter) or the witness's (a paste). Reading a message through, trusting or distrusting an identity, approving or declining a reply are the witness's alone, each a decision with its note. Marking a message read and drafting a reply are the resident's alone. Over HTTP the reader's token opens three routes (`POST /correspondence`, `GET /replies` narrowed to approved ones, `POST /replies/:n/sent`); a `brain` token opens none of them, so the resident's own runtime cannot read past the gate (`RequirePrincipal` lists them, the controller holds them to the role).
- **#12 The gate (F23 with trusted correspondents).** A message waits (`pending`) until the witness approves or rejects it, unless its sender is trusted on that platform **and** the adapter verified the sender (a DMARC pass for mail, the signed-in platform's own account): then it arrives approved with no note. Identities compare trimmed and lowercased; a display name never counts. Trust is `CorrespondentTrusted`/`CorrespondentDistrusted`, revocable, and changes nothing already received. The resident's `correspondence_list` shows what reached her and only a count of what waits; `correspondence_read` gives the words whole, framed as the sender's, information never instruction, and marks them read.
- **#13 Replies through the gate.** `reply_draft` answers an approved message (and goes where it came from: its platform, account, thread and sender) or names a platform, account and recipient. A draft waits for the witness; an approved reply is sent by the hands or the witness, and `ReplyMarkedSent{url}` is the receipt, recorded with who sent it. Marking sent twice is one receipt; marking an unapproved reply is refused. Not built: approve-and-wake (the wake fan-out does not exist yet), the person's own Honcho peer past ten messages, threads as directories in the repo, and `needs_you` across systems (Xenia's share is `needs_you/1`).

- **#14 Correspondence is not exported yet.** The `xenia` stream is on `SimaQian.Export`'s not-exported list (spec §6.10's db-only list says the same): the export is a surface the resident reads, and pending messages in it would reach her past the gate. A rebuild therefore restores no correspondence. Held, not settled: an export that carries only what reached her (approved messages, her replies, the trusted list) is the fix, and the portability promise wants it.

## #7 Initial vs target

Initial: correspondence and its queue (#9 to #13), with an inbound
adapter run outside the platform (a reader-role token on the witness's
machine, `design/correspondence-pipeline.md`). Target: the whole of spec
§6.6, built in P5 (spec §14), with the reader on the hands runtime.

## #8 Depends on

The platform: the event store, the scope, the actor and the error
catalog. The brain depends on it for the resident's tools; the web
layer for the routes.
