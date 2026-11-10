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
  It answers from the cross-kind search (kumbukumbu#59): every scope,
  typed results with their kind, title, day and snippet. A record or a
  scene opens in Records, a bookmark as its citation, and her words open
  the conversation at that turn (`#/chat/turn/<session>/<turn>`); a turn
  in another session switches to Conversation but cannot open there yet,
  because no transcript reader for other sessions is built.
- **ScrollArea.** Edge fades as a mask, shown only while there is more
  past that edge.

**Motion** (`shell/motion.ts`):
- Tabs dissolve. The leaving tab stays shown and inert under the
  arriving one while it fades; no tab is remounted.
- The dissolve goes through the ground: out 110 ms, then in 150 ms.
  The witness chose it over a direct crossfade from a side-by-side
  recording (2026-11-10): the crossfade barely registered as a
  transition.
- Pushes slide on a phone: deeper comes in from the right, back from
  the left, a short distance with a fade, without remounting the view.
  On a wide screen the list sits beside the page, so nothing slides.
- Reduced motion makes all of it instant.

Not built: the subject menu with its fade out, load, fade in (it
carries the theme swap, P8), and theme seeds
from the server (S7). Sign-in reuses the current client's form until
onboarding (P6).
