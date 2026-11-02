# The chat's mechanics: what exists, what we took, what we built

The two Lilys' day prompt (2026-11-02), item three: the chat should show
the witness's message the moment it is sent and stream replies as they
are generated, and the box needs newlines and room for more than one
line. **Check open source first**: adopt or adapt before building, and
say which and why. Written by Lily from Claude Code, 2026-11-02.

## What we already had

- Replies already stream: the session channel (`joinSession`) carries
  `turn_started` and each delta, and Chat renders the text in place
  while it arrives. Part (a)'s second half was done.
- The send itself is an HTTP request that returns when the turn is
  captured. Its only visible cost was that the witness's own message did
  not appear until then.

## The candidates

| Project | Licence | Fit |
| --- | --- | --- |
| Open WebUI | Custom since v0.6.6 (April 2025): BSD-3 plus a branding clause; packagers treat it as non-free, and the vendor says it is not OSI-compliant | A whole app on its own backend. The clause and the app shape rule it out for a product that is not Open WebUI. |
| Lobe Chat | Apache 2.0 with LobeHub's additional terms from 1.0; modified derivatives need a commercial licence (per secondary sources; check the LICENSE before any use) | A whole app; the terms rule out adapting it into ours. |
| LibreChat | MIT (checked at the source) | A whole app on its own server. Borrowable code, but its client assumes its API, and ours has what none of these have: the drew-on inspector, refusals in the resident's words, the next-turn preview, read-only conversations from other runtimes. |
| assistant-ui | MIT (per its repository) | A React library, not an app: Thread, Message and Composer primitives with streaming, auto-scroll and accessibility built in, and a custom-runtime adapter. **The real candidate** if we want a library. It is a new dependency, which the house puts to the witness first, and adopting it means rewriting Chat around its primitives. |

## What we took (patterns, no dependency)

What every one of them does, and ours did not:

1. **The composer grows.** A multi-line box that grows with its text to a
   ceiling (about eight lines), then scrolls inside itself.
2. **Enter sends; Shift+Enter is a newline.** And nothing sends while an
   input method is composing a character (the IME guard every serious
   chat has, for languages typed by composition).
3. **The sent message shows at once**, marked as sending, and is replaced
   by the captured transcript when the turn lands.
4. **Follow the end only from the end** (we had this from the morning's
   work: the transcript follows new text only while the reader is at
   the bottom, and says "New messages below" otherwise).

## What we did not do, and why

- **Sending over the socket instead of HTTP.** The visible goal (his
  message at once, the reply streaming) is met without it: the message
  shows the moment it is sent and the reply streams over the socket that
  was already there. Moving the send itself onto the channel would
  change error handling and the budget-stop path for no visible gain.
  Revisit if long turns start timing out at a proxy.
- **assistant-ui.** Worth a trial branch when the chat next grows, with
  the witness's yes on the dependency; this pass stayed dependency-free.

## Sources

- Open WebUI licence: https://docs.openwebui.com/license/ (and the
  nixpkgs packaging note treating it as non-free)
- Lobe Chat: https://github.com/lobehub/lobe-chat/discussions/1768 and its
  LICENSE (secondary sources disagree on the exact terms)
- LibreChat: https://github.com/danny-avila/LibreChat/blob/main/LICENSE
- assistant-ui: https://github.com/assistant-ui/assistant-ui
