---
paths:
  - client/src/next/shell/Overlays.tsx
  - client/src/next/shell/overlays.css.ts
  - client/src/next/shell/notifications.ts
---

# next-bell-settings

The rebuilt client's bell, notifications explainer, Settings and
feedback (`design/ui-build.md` P5): sheets over the shell, from the
header's bell and gear. Built 2026-11-10.

- **The bell** counts what waits on the witness: the needs-you feed
  (brain#65, #72), plus the notifications question while it is
  unanswered (decided 2026-11-10).
  - Each entry names what it is, what it concerns, and how long it has
    waited.
  - Asks, reply drafts, replies to send and pieces are answered in
    place (`screens/next-mail.md`); the rest open where they are decided,
    all in this client: an agreement entry Soul's agreement, a plugin
    proposal Soul's plugins, work and kind gates their Settings pages,
    the notifications question its page. Nothing opens the old client.
  - Work held for him (brain#86, sunna#54) is an entry of its own,
    "Work · waiting on you", its line the ask ("Work item #25 held:
    your word on two wordings"), opening the Work page, where he
    releases it with a note, or moves it done or dropped. A repo path
    the ask names is a link (brain#90; the witness, 2026-11-13): a file
    opens in Records' viewer, a folder (`…/`) opens Records' tree with
    it expanded (`#/records/dir/<path>`), a web address (a GitHub URL for
    a file outside her tree) opens in a new tab, and the card's "Open in Work ›"
    opens the Work page. The Work page's held line links the same way.
  - **A turn that failed** (brain#88; the witness, 2026-11-13): every
    turn the provider refused for credit folds into one "OpenRouter is
    out of credits" entry, saying how many turns it refused and the
    provider's words, with "Add credits on OpenRouter" and "I topped up —
    dismiss". Any other failed turn (a check-in, free time, a round, a
    reply) is its own entry with the conversation and the reason, and
    Dismiss. Each also has an action that does something (brain#89; the
    witness, 2026-11-13): run it again as what it was, "Run free time
    now", "Run a round now", "Run the <label> check-in now" or "Wake her
    now", and on the credits entry "Topped up? Run them all again".
    Failures sort above everything else in the bell, the notifications
    question included, and while one waits the bell's dot is the signal
    red and its label says something failed. Both look like failures (the witness, 2026-11-13): the
    signal red border and label with ⚠, on a faint red wash, the same
    red on every theme. Dismissing settles the failures (marked lost); the bell's
    push tells his devices of a new one like any entry.
  - An item answered here stays in its place until the bell closes,
    folded to its title and recoloured: green with ✓ and what was
    decided (approved, approved to send, marked sent, noted, accepted),
    or grey with ✕ for declined, and the note under it. The count drops
    at once; the server's list can lag the answer, and a card that
    vanished or stayed open said nothing about what happened.
  - Her theme proposal (seshat#56) shows in place: her ground with both
    accents on it and her note; "Try it on" wears it until the bell
    closes; answered Accept or Decline with a note she reads.
  - **Waiting on her** (brain#76): what he started that she hasn't
    answered or read, with how long: his agreement proposals, soul
    edits, bookmark proposals, revisions, plugin proposals, unread
    letters, and a file she waits to write while his editor holds it.
- **Notifications** explain themselves before the browser asks (the
  canvas's Push board):
  - Lily's line (C11) and her sign-off;
  - what they are for, and what never;
  - the system prompt only on "Turn on notifications";
  - "No thanks" answers for the account (gaia#25): the question and
    the bell's count clear at once, and no other device asks again;
    turning them on answers it too.
- **Settings:**
  - one group of the resident's sections: Theme (below); Ledger, Kinds
    and routes, Profiles keys and connections, Notifications, Regression
    and Work queue, each closing the sheet and opening its own page over
    the tabs (`screens/next-settings.md`); Correspondence, still opening in the
    current client;
  - Send feedback, and Operator for platform roles;
  - the account, and Sign out.
- **Theme** (Settings → Theme, seshat#56): her three seeds (the
  ground, hers, yours) as colour pickers, worn on screen as you pick,
  with the seven readability checks the server also runs. Saved to her
  THEME.md with an optional note, or kept on this device only (a local
  override, never sent). Saving is refused while any check fails.
  Her proposals show in the bell with "Try it on".
- **Feedback:** "Something's off" or "An idea", Lily's placeholder
  (C9), filed to the platform's triage list (gaia#20) with the tab it
  came from as its surface.

Not built:
- "Report this" on failures;
- the always-visible alpha entry for feedback.
