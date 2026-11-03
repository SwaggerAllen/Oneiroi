---
paths:
  - client/src/screens/chat/**
---

# chat

Chat (home) (spec §10). Built (P1, slice 5) as `Chat` with `ChatContainer` in the shell: the transcript with refusals in the resident's words, the streamed reply over the session channel, "drew on N things" over the turn's injections, a bookmark proposal from a reply, and "What Lily will see next", the preview of the next turn (brain #41).

The preview sits beside the inspector: the inspector is what a turn drew on, the preview what the next would, from `POST /v1/residents/:id/sessions/:key/preview` with the draft as it stands. The server sends every section in its order with label, tokens, reason and its words, whole by default (under the contract's `preview_withholds_words` term, only where you already read them elsewhere, a line saying why otherwise), never a once-only notice's words before it is told, and a description of the whole; a reply's inspector shows the notices that turn told, with their words; the client renders them and decides nothing (which sections exist, their order, their counts, what is withheld). Opening it records nothing and bills nothing; sending closes it. The other conversations (`Conversations`, kumbukumbu #40) sit folded under the top bar: the Oneiroi chat first, then every other conversation from `GET /v1/residents/:id/sessions` grouped under the `title` the server gives it (a Claude Code one is `Claude Code · <folder>`), groups and rows in the server's order, last spoken in first, each row when and how many turns. One the server says is not `writable` opens read only: its transcript and each reply's inspector (the transcript route sends each turn's `drew_on` count), no composer and no preview, and a line saying it is answered where it happens. The client groups by the server's title and decides nothing about what a conversation is. Long words wrap on a phone. The state list lives in the stories alone (DESIGN §4); nothing here names a state. The shell is the screen's height (`100dvh`) and never scrolls itself: the top bar, the composer and the nav stay in place and only the transcript scrolls, and every message wraps inside the width (`overflow-wrap: anywhere`), so a wall of text or a long URL never widens the page past the phone (the resident's work order, 2026-11-02: "the UI is never the right size for the screen"). The transcript is read in pages of fifty from `GET .../sessions/:key?limit=&before=` (each message's `cursor` is `sequence:position`, `more` says whether earlier ones remain): it opens on the newest, pages back as the reader nears the top without moving what they are reading, re-reads the newest page when a turn lands and keeps what was paged in, and follows new messages only from the end, offering "New messages below" otherwise. A divider, "New since you last read", sits before the first message someone else wrote after the last one read on an earlier visit, held where it was for the visit, with "Back to where you left off" while it is above the view; the place is kept per session in the browser and only moves forward (her amendment: whether the witness has been reading stays legible). A tool call longer than a short line starts closed on its first line, cut to the width, and its size in lines and characters, and opens to every word. The composer grows with its text to about eight lines and then scrolls inside itself; Enter sends, Shift+Enter is a newline, and nothing sends while an input method is composing. The witness's message shows the moment it is sent, beside the reply streaming in, until the captured turn replaces it: it sits in the outbox (`outbox.ts`, brain #45), each message under its own ref, kept in the browser per conversation until its turn lands with a reply, and sent with that ref (`POST .../sessions/:key/turns` with `client_ref`), so sending never waits for the last reply. Under each is where it is: sending…, queued, delivered, "not sent yet: no connection" or "not sent: " with the server's words, and "Lily couldn't answer" when the turn ran and no reply came. An unsent message goes again by itself under the same ref when the stream comes back and every ten seconds while connected (up to thirty attempts), unless the server refused it for what it is (a 4xx other than 408 or 429); a refused or unanswered one offers Retry (unsent, same ref) or Send again (failed, a new message), and Dismiss. What the browser kept from before a reload comes back as not yet sent and goes again. The top bar carries a connection dot (`ConnectionDot`: connected, connecting, offline, said in words to a screen reader and on hover) and, while a message is on its way, what the resident is doing from the session channel's status (Sending…, Queued: Lily is finishing another reply, Lily is thinking…, Lily is using <tool>…, Lily is writing…); otherwise "Main conversation · last reply on <model>", the model recorded on the last reply. Both the drew-on inspector and the preview open on an overview, every section closed to its label and size, each opening to its reason, words and note, with Open all and Close all. Not built: the check-engine light, the session line (last and next check-in), reports, opening a cited target in the panel, pinning from a reply, and the menu (search transcripts, open a new session, file a report). The survey behind both, what open source offered and why we took patterns rather than a project, is `design/chat-ui-survey.md`.

## #1 Shows

The main conversation as a transcript; the other conversations apart, Claude Code's grouped by folder, newest first, each read only (the author, round 49: "Claude and Oneiroi chat are two different use cases"); the check-engine light and the session line (last and next check-in) in the top bar, with the model the last reply was recorded under, so a pin that did not take is visible here rather than found by asking the resident; refusals in the resident's words; a "drew on N things" inspector per reply; the preview of what the next turn would be given; both open on an overview, every section closed to its label and size, each opening to its reason, words and note, with Open all and Close all (the author asked for an overview to dive down from, after the first preview showed every section whole at once); reports filed by either party and each investigation step inline.

Brain #45: messages on their way are an outbox, each under its own ref
with where it is (sending, queued, delivered, not sent with Retry, not
answered with Send again); the top bar carries a connection dot and,
while a turn runs, what the resident is doing (thinking, using a named
tool, writing). Sending never waits for the last reply: the next
message queues.

Client #13: coming back to the page (the tab shown again, the window
focused, the network back) reads the open conversation and the list
again, and joins the stream again with a fresh token when it was down
or the page was away more than thirty seconds, so turns that landed
while a phone had the page suspended show without a reload.

## #2 Does

Send; open another conversation and read it; open a cited target in the panel; pin or propose a bookmark from a reply; search transcripts, open a new session, file a report from the menu.

## #3 Rules from the design system

Approve-and-wake exists only where a wake makes sense; every other
approval is reject or approve. A destructive action confirms once in
place by the button changing to its consequence, never in a modal. A
number the spec calls a bound says so beside it. Nothing says "AI", "the
model", "generate", "regenerate" or "error" as a heading, and "AI
refused" is never a feedback option. The client says Lily, you, your
agreement with Lily, who looks after Lily; the schema's words appear
only in settings and contract copy or not at all.
