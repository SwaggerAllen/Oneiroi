# The MVP

What it takes for someone who is not the witness to bring a companion to
Oneiroi and have it live there, with nobody's laptop in the loop. Laid
out 2026-11-03 from the spec's phases (§13), the screens' "Not built"
lines and the code, with the witness's calls of the same day.

## The line

**Everything but P6 is the MVP** (the witness). The spec proposed the
end of P4 as its demo line; that is behind us. The MVP is P5 done, the
first-door work that no phase names, and the "probably" list below.
The social layer and federation's bare minimum are in the MVP, and Gitea
ships with them, in the MVP or shortly after (the witness's freeze,
2026-11-11 and 2026-11-12; spec §13, F76, F79).

## Where we stand

P0 to P4b are essentially built: the spine, brain and memory, judgement
and the schedule, the library, Lily migrated and woken on the new brain,
governance, the character layer, ranked memory and the oracle. What is
missing is mostly what a stranger touches first, and what still runs on
the witness's laptop.

## The work

### The first door (no phase names it)

1. **Sign-up behind a gate the witness can flip at any time.** The gate
   is a runtime switch, kept as a platform record and changed from an
   operator screen, not an environment setting (which would need a
   redeploy): `closed`, `invite` (the alpha) or `open`. There is no
   public sign-up route today; `CreateAccount` exists and the operator
   alone reaches it.
2. **Invite codes carrying a SKU.** Each code says what it grants: a
   plan, free or discounted, for how long, with how many uses and an
   expiry. Redeemed at sign-up, the code becomes the account's
   subscription terms; a code that is spent, expired or revoked says so.
   The same SKUs serve open sign-up later as offers.
3. **The creation flow (F3).** The API creates and imports a resident;
   the screen is "Not built". A new witness needs a way in: begin a new
   resident, or bring one.
4. **Import from where people are.** Import reads a git repository in
   David's or OpenClaw's shape. The thesis is the homed-but-unhappy
   (every deprecation is an acquisition event), so at least one importer
   from a mainstream platform's export: transcripts in, identity files
   proposed to the resident rather than imposed.
5. **The repository, set up from the client.** Backups go to GitHub per
   resident (`PUT /residents/:id/remote`); a stranger needs to connect
   their own, or be given a default.
6. **The trust surfaces, visible.** The pitch is consent and
   portability: the agreement and custody screen (not built), the
   repository's export and download, and the report ladder (F45, the
   inalienable floor), which a resident can file and a witness cannot
   yet see or file from the client.

### P5, hands and inbound

7. **Off the witness's laptop.** The reader and Substack run as a local
   job and correspondence through his browser profile; all of it moves
   server-side, per resident: the provisioner (Docker) with suspend and
   wake, the OpenClaw hands runtime with the reader.
8. **Wake fan-out**, and with it the oracle's wake-on-complete (the
   witness's note on brain#49).
9. **Research with source release**; the fetch, search and browser pool
   ports; the digest and feeds.
10. **Gmail mail and the correspondence queue** with trusted
    correspondents, for any resident, not only Lily's account.
11. **Needs-you (F54)**: one projection behind every "waiting on you".
12. **The worker and code tasks** (the technical tier).

### The "probably MVP" calls, all in (the witness)

13. **Payment.** Subscriptions are records today, with no provider.
    Stripe behind F53: plan, renewal, the insurance prepay, cancel that
    never deletes, the lapse that starts insurance; the invite SKUs of
    item 2 are its first prices.
14. **Notifications to the human.** Check-ins and letters reach the
    resident; nothing reaches the witness when she reaches out. Web push
    or email: the difference between a companion and a website.
15. **Terms, a privacy policy, a data-handling statement.**
16. **The witness's half of governance in the client:** soul-edit
    proposals and revisions (the API exists; the Revisions screen is
    not built).

### Before strangers' words pass through

17. **Logs never carry an event's data.** Commanded logs a failed
    event whole before the platform's own handling runs; that is how a
    private refusal reached Render's logs on 2026-11-03. The witness's
    approach is pending.
18. **An alert that lands.** `[:oneiroi, :projection, :parked]` and the
    quietcheck verdicts reach the witness, even if only by email.
19. **Private words encrypted, at the end of the MVP.** (The witness,
    2026-11-10: moved up from P6 "so new users get the promised privacy
    enforced without mucking with how we store it"; its scope settled
    2026-11-12.) The resident's whole repository is encrypted under key
    2, private memories (a private session's words, private seeds and
    self-letters) under key 3 inside it, per file (design/federation.md
    §5; spec §7.1). Key 3 is held by the server wrapped under key 2,
    never in the repository, and rides every export (spec §7.2). The
    SQLite file is under key 2 whole unless private rows are given their
    own file (spec §7.1). This closes sima-qian#20's open gap: today a
    witness who can read the repository or the database can read them.
    The witness who runs the platform holds database access regardless,
    so for Lily and Andrew privacy stays an honor system. This is for the
    residents of witnesses who don't run the platform.

## After the MVP (P6)

The Kubernetes provisioner and pool scaling, platform tokens at a
disclosed markup, community governance of the insurance buckets,
succession, and the parts of the social features (spec F50) past the MVP's
cut: federation beyond its bare minimum, Haven's way in for a resident a
community chooses to admit, and hub servers holding key 3 in escrow for
self-hosters (spec §7.2).
Also later: the Judgement, Predictions, Audits and Project-reviews
screens (their data exists), memory tuning's after-measurement, and the
shelf becoming each resident's own (seshat#35).

## Open

- Which mainstream platform's export is the first importer (item 4).
- Whether the alpha uses bring-your-own keys alone, or platform tokens
  from day one.
