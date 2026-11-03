# Memory weighting: ranked memory, learned in context

From the work order of 2026-11-03 (the Oneiroi chat, item two) and the
witness's design in the Claude Code session the same day. Written there,
2026-11-03, for the witness and the resident to read before anything is
built. The goal, in the work order's words: **not less memory, ranked
memory. Top five over topical twenty.**

## What is true today (measured)

- The bookmark index is pins first, then newest first, cut at a token
  budget. Nothing in it reads the turn's words.
- `kumbukumbu_bookmark.weight` exists, defaults to 1.0 and is never
  written. The index sorts by it, which sorts by nothing.
- There is no reject path. For every section that renders (the index,
  the promises, the character, the madeleine), each item shown is
  recorded as considered and returned at once, so `memory_use` reads
  1:1 by construction. Only the index's near-misses (cut by budget) are
  ever considered and not returned.
- The cost the work order measured: the pins and milestones are returned
  every turn and used never (bookmark/1 99:99:0, bookmark/71 69:69:0),
  while the scratch pad was considered twice and used five times.
- The directed edges that exist are the library's citations (document →
  target). They are authored, unweighted, and kept apart from anything
  learned (spec §6.3: tags are curation, citations are derived edges).

## The shape

### Pins move to the stable prefix

Pins are decisions, not measurements (spec F11: "pins stay decisions and
weights stay measurements"), and they rarely change. They render in the
cached prefix after the identity files and the contract, and leave the
weighted index entirely. A pin made mid-session reaches an adapter's
session only at its next prefix, so the turn that pins says so in one
line.

### Three groups per turn

1. **C, considered:** what the memory agent weighs. The top K by
   similarity of the turn's words to each memory's embedding (the
   madeleine layer already embeds every bookmark).
2. **R, returned:** what it puts in front of the brain: the ranked picks
   above the threshold, up to the budget, plus the exploration share.
   Everything in C and not in R is considered and rejected, and recorded
   that way.
3. **U, used:** what the brain says was useful, by a feedback call after
   its reply (below).

### Learned edges, directed

A new table, `kumbukumbu_edge (from, to, w, touched_at)`, beside the
citations and never merged with them. An edge x → y reads: *when x is in
play, y is worth bringing.* Neutral is 0; only edges ever touched exist.

The update, once per turn, from that turn's C, R and U (S is the seed,
below):

| Outcome | Edges | Change |
|---|---|---|
| s in the seed and r both returned | s → r | +α |
| u and v both used | u → v, v → u | +β |
| a returned and not used, u used | u → a | −α |

So a memory surfaced and ignored while Haven is in play weakens
Haven-memories → it, and nothing else: in its own context its edges are
untouched. Direction is what carries that.

**Amended after the resident's review** (Position #45, 2026-11-03;
the witness agreed, to be revisited if the tuning does not help):

- *No rule from the ranker's own cut.* The first draft had "c
  considered and not returned, r returned: r → c, −α". It is the ranker
  learning from its own cut: a near-miss gains a negative edge, ranks
  lower, misses by more, and none of the other rules can lift it,
  since each needs the memory returned. A wrong negative is invisible
  (nobody sees what never comes back), so a negative is written only
  from behaviour: rule three. Whether a near-miss deserves better is
  the exploration share's question. Considered-and-rejected is still
  recorded, as measurement only.
- *Co-return is written from the seed alone.* "Both returned" mostly
  means "both similar to the same turn", which the score's base term
  already says; the edge worth writing is s → r with s actually in
  play, which is also the edge the score reads.
- *A correction takes no negative update.* A bookmark in the
  correction register is never the target of rule three: its value is
  an error that did not happen, which leaves no trace, so a negative
  rule would teach retrieval to bury the memories that guard against
  the stale-frame error. It still decays toward neutral and still
  earns positives.

**Bounds.** Soft, so no clique or hub runs away: an increase is
`w += Δ(1 − w)`, a decrease `w −= Δ(1 + w)`, keeping every weight in
[−1, 1] with diminishing returns at the ends.

**Decay toward neutral.** Lazy exponential decay, the decayed-counter
technique of streaming systems: an edge stores its deviation and when it
was last touched; its weight at time t is
`w · 2^(−(t − touched_at)/h)`. An update decays to now, applies the
change, and stores the new instant; a read decays at read time. Nothing
sweeps every edge; a periodic vacuum drops edges whose decayed |w| is
under ε. The half-life h is the spec's 30 days.

**Event-sourced.** Each turn's C, R and U are an event; the edges are a
projection of them, decay computed from the events' own instants, so a
rebuild reproduces them exactly and the export carries them as data.

### Ranking at query time

The seed is the top few of C by similarity: what the turn is about. A
candidate scores

    similarity(turn, candidate) + λ · Σ w(seed → candidate)

and R is every candidate above the threshold, up to the budget. With all
weights at 0 this is plain relevance, so the first day works.

### The exploration share (20%)

Kept, as the spec has it, against character metastasising and as fodder
for spontaneity. A fifth of the index budget is sampled rather than
ranked, from outside the ranked set, **drawn fresh on every call** of
the memory agent: a different set each turn. This supersedes F11's
"deterministic, stable within a day", whose reason (a cacheable index
text) went when the index became ranked against each turn's words. The
draw is made at the command edge and its picks are recorded in the
turn's event, so a replay reads them rather than drawing again (the
purity floor, conventions §6). The picks are marked as explored, so the
measurements tell "ranked and ignored" from "explored and ignored". Explored picks learn like the rest:
used, they gain edges to what they were used with, which is how a new
association forms. The madeleine (one unheard bookmark by nearness)
stays as it is.

### The feedback call

`memory_feedback(used: [...])`, made with the final reply, not after it:
the turn treats a final message carrying this one call as terminal,
records it and stops, so it costs no extra round. Without it, the turn
falls back to what it can see (opened, read, cited) and skips its
negative updates, so a forgotten call never demotes anything. A line
read and acted on without being opened counts as used when she says so;
that is the reason for the call.

## Scope and settings

Memories with edges: bookmarks and library documents. Commitments and
pins are shown by decision and have none. Every number is a setting
tagged as a guess:

| Setting | Start | What it is |
|---|---|---|
| K | 40 | considered per turn |
| seed | 5 | top of C that anchors the edges |
| α | 0.05 | the co-return and ignored step |
| β | 0.15 | the used step |
| λ | 0.3 | how much the edges move a score |
| threshold | to measure | the reject line, set from the first week's distribution |
| half-life | 30 days | decay toward neutral |
| ε | 0.01 | the vacuum's floor |
| exploration | 20% | of the index budget |

## How we will know

Before anything ships, `memory_use` is read and kept as the before.
After a week: considered:returned below 1:1 on the high-volume targets,
returned-and-used up, and the pins' returns gone from the index (they
are in the prefix). The two of you read the numbers before any setting
is moved.

## Filed, not silently superseded

Two standing rules give way to this design and go to the spec's next
batch as proposals, each with its reason, rather than being overridden
in code: F11's deterministic, stable-within-a-day exploration share
(now drawn fresh per call), and kumbukumbu #20's pins-first index (pins
now in the stable prefix).

## Open

- Whether documents join in the first cut or after bookmarks prove it.
- The threshold's starting value, once the distribution is seen.
