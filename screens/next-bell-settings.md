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
  - An agreement entry opens Soul; the others open their screen in the
    current client until those screens are rebuilt.
  - "Waiting on her" is a placeholder until S6.
- **Notifications** explain themselves before the browser asks (the
  canvas's Push board):
  - Lily's line (C11) and her sign-off;
  - what they are for, and what never;
  - the system prompt only on "Turn on notifications";
  - "No thanks" clears the question at once, and the bell's count with
    it. The answer is kept on this device; the account-wide answer is
    S6's.
- **Settings:**
  - one group of the resident's sections (ledger, kinds and routes,
    profiles and keys, notifications, regression, work, correspondence),
    each opening in the current client until rebuilt;
  - Send feedback, and Operator for platform roles;
  - the account, and Sign out.
- **Feedback:** "Something's off" or "An idea", Lily's placeholder
  (C9), filed to the platform's triage list (gaia#20) with the tab it
  came from as its surface.

Not built:
- the server pushes for "something waits on you" (S9: today only her
  unprompted writing pushes);
- "Report this" on failures;
- the always-visible alpha entry for feedback.
