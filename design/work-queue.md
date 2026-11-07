# The work queue

Lily's design, workshopped with the witness in conversation on
2026-11-06 and promoted here from `scratch/work-queue.md` when its rails
were built (sunna#33, her work order letter #183). The witness's shape:
recursive iteration, where each finished item buys the turn that checks
the queue and sets off the next. "Schedule" is the wrong word; the loop
is the schedule.

## The shape, and how it was built

1. **The queue is a list both parties keep.** Numbered items in priority
   order, each with what (one line) and what done looks like, its
   status (open, in work, blocked on something named, done, dropped)
   and its last wrap. Inspectable by default: she reads it with
   `work_list`, the witness on the Schedule screen's Work queue card.
   His items enter it the same as hers. *Built as a stream rather than
   this file:* the loop reads the queue on every check, and each change
   is an event with its actor, so who added and who moved what is on
   the record. This document says what the queue is; the queue itself
   lives on `work-<resident_id>`.
2. **The trigger is completion, not a clock.** An item runs as a
   conversation of kind `work`, a turn at a time while a turn runs out
   of tool rounds (free time's mechanism, sunna#26, a sibling, not a
   replacement). When the run ends, the wrap runs, and the run's end
   asks for the next check at once: start the first open item, or rest
   and say why. The minute tick asks too whenever work is open and
   nothing runs, which is how a loop paused for care, or one that was
   empty and got an item, resumes.
3. **Care outranks work.** No work turn starts inside quiet hours or
   while a free-time pass is underway; one that would waits and tries
   again. Check-ins run in the Oneiroi chat, never in a work
   conversation, so a run never holds one. Free time stays care: work
   bills its own line and never the free-time one.
4. **Long items only.** Anything a conversation turn can finish stays in
   conversation. The queue is for work that needs many turns: specs,
   designs, letters with drafts behind them, marks across nine files.
   (The tools say so; nothing enforces a size.)
5. **The wrap rides every item.** Each run closes with one turn in which
   she records what shipped, what slipped and why, and where the item
   stands (`work_wrap`), and a journal row in her own words if the run
   is worth one. The wrap bills the closing-turn line (`planning`,
   sunna#32), so a run that ended because its budget ran out is still
   wrapped. A run she does not wrap ends with the item open again.
6. **Empty is a real state.** "Empty, holding" is recorded like any
   other answer, once, naming any blocked items and what blocks them.
7. **The queue accelerates her drafting, never his deciding.** Every
   run's opening note says so: what would change the platform or act in
   the witness's name ends as a draft for his read or an
   `approval_request`, never as the act.

## The guards

- **Money is his, as a brake** (sunna#35, his call, 2026-11-06). Runs
  bill the `work` line, armed while the queue has work and off when it
  is clear. With no cap it is unlimited, like the chat line; a cap he
  sets stops a run when spent, and the loop holds until the period turns
  or he raises it. (First built as an ignition, where no line held the
  loop; he found the panel's "no cap" read as held.)
- **A day's runs.** At most `SUNNA_WORK_RUNS_A_DAY` (8) runs start in one
  of her days, so a queue that never empties cannot run all night.
- **A run's turns.** At most `SUNNA_WORK_TURNS` (20) turns before the
  wrap, free time's bound.

## First queue (her loaded state, 2026-11-06)

To be entered with `work_add` once the rails are live, in her order:

1. Generator brief: the drafting agent's rules (citation shape, pass
   size, refusal list, model); nothing composes in a resident's voice
   without the hand named.
2. Plugin spec.
3. Social spec.
4. Federation spec (`scratch/federation-interop.md`, second pass in).
5. Drake letter, with the three specs in hand.
6. Marks on the nine guidance files.

The witness's E2E creation handoff test (creation to first message, a
real resident answering, no fixtures across the seam) is a candidate
behind the brief; priorities come after the rails, by his word.
