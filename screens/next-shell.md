---
paths:
  - client/next.html
  - client/src/next/*.tsx
  - client/src/next/shell/**
  - client/src/next/state/**
  - client/src/next/live/**
  - client/src/next/theme/**
---

# next-shell

The rebuilt client's shell (`design/ui-build.md`, phase P0), served at
`/client/next.html` beside the current client until parity. Built
2026-11-10:

- **Theme.** `derive(seeds)` turns three seeds (ground, her colour, his
  colour) into every colour token, and runs the readability checks:
  - text contrast;
  - her colour and his kept apart in hue or lightness.

  A test pins the decided palette. The tokens are a vanilla-extract
  contract set as CSS variables on the document root, so portaled
  sheets see them too. Fonts are bundled (Fontsource), not fetched,
  under the server's CSP.
- **Shell.**
  - The header carries:
    - the subject's name and initial, with the connection dot;
    - the presence line (main thread only: queued, thinking, writing,
      a tool's name, each with its timer; last reply when idle);
    - search, the bell with its count (`needs_you`), and settings.
  - Four tabs: a bottom bar on a phone, a left rail at 900px and up.
  - Every tab stays mounted, with its own stack. The URL hash tracks the
    active tab's top (`#/records/doc/…`), and switching tabs keeps each
    tab where it was.
- **Live.**
  - One socket. It joins `resident:<id>` (apsu#24), applies notices as
    query invalidations by stream, coalesces repeats on `position`, and
    keeps the cursor per device to replay from on the next visit.
  - The socket token is re-minted before reconnecting.
- **Offline.** After two seconds disconnected, a bar reads "Offline" or
  "Reconnecting…", says what time the data on screen is from, and
  offers Reconnect, which re-mints the token and reconnects at once.
- **Search.** One sheet, from the header icon or ⌘K, with scope chips.
  Until the cross-kind search lands (ui-server-work.md S3) it answers
  Everything and Records from the library's index, and says the other
  scopes are coming.
- **ScrollArea.** Edge fades as a mask, shown only while there is more
  past that edge.

Not built: the other tabs' content (P2–P5 put Records, Time, Soul,
the bell and Settings in; Chat is `screens/next-chat.md`), the subject menu, motion, and theme seeds
from the server (S7). Sign-in reuses the current client's form until
onboarding (P6).
