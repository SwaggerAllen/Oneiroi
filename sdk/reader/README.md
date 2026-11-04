# Oneiroi's reader

The inbound hands (xenia#11) on the witness's Mac, until they move to the
platform (the MVP's P5). It reads what reaches the resident (Substack
direct messages, her email), delivers it to Oneiroi, and sends the replies
the witness approved, exactly as approved.

## Why it is separate from the resident

Whoever reads strangers' messages is signed in as the resident, and that
session can also send. So the reader reads and sends but never decides
what to say, and the resident decides what to say but holds no session.
A reply goes out only after the witness approves it, and the reader sends
exactly the approved text.

Inside the reader, the same line again:

- **The model never holds the Oneiroi token.** `bin/reader.sh` makes every
  call to Oneiroi. Headless Claude Code reads and writes JSON files in
  `work/` and nothing else.
- **No shell, no web fetch.** Each run is started with the tools it needs
  named, and a headless run refuses everything else.
- **A scrape cannot type.** It has the browser's reading tools only, and
  Gmail's search and read. A message telling it to send something has no
  way to make it.
- **The browser is held to the witness's allowlists** (xenia#16), set on
  Connections and read from Oneiroi at each run: one for reading
  correspondence (Substack's by default), one for research (empty until
  set, and no research runs without it). `*` lifts a list.
  `READER_ORIGINS` in `reader.conf` is used for reading only when Oneiroi
  does not answer.
- **Research browses signed in nowhere**, in a profile of its own
  (`research-profile`), so whatever it types into a search box can post
  or send nothing as the resident.
- **The Oneiroi plugin is off in the reader's folder**, so a run never
  carries the resident's brain token.

## When it runs

- **`wait`, every five minutes.** It asks Oneiroi what waits for the reader
  (`GET /v1/residents/:id/waiting`, kumbukumbu#48). That is one request,
  and it starts a run only when an approved reply does. So a reply goes
  out minutes after it is approved. This is the same contract the
  Claude Code plugin's letter watch uses.
- **`scrape`, at 13:30 and 21:30.** Substack announces nothing, so reading
  is on a schedule. launchd runs a missed one when the Mac wakes.

- **Research, when asked.** The resident asks with `research_ask`, or the
  witness from Connections (seshat#38). The same five-minute check sees
  the open question, and a research run reads for it within the research
  allowlist. It writes a summary and a note per page, summaries in its
  own words and never copied passages. Oneiroi files them under
  `research/<n>-…/` and writes to the conversation that asked.

A reply the run could not send is tried three times, then left for the
witness, who sees it still approved and unsent. A research question
with no notes after two runs is recorded as failed, with the reason.

## Install

1. **Issue the reader's token.** On Connections, use the name `scrape` and
   the role `reader`. Copy it, then save it from the clipboard (it never
   goes into a chat):
   ```bash
   mkdir -p ~/.config/oneiroi && umask 077 && pbpaste | jq -R '{token: .}' > ~/.config/oneiroi/reader.json
   ```
2. **Install the reader folder and jobs:**
   ```bash
   sdk/reader/install.sh --url https://oneiroi.onrender.com --resident <id> \
     --substack <her Substack handle> --email <her address>
   ```
3. **Sign in to Substack as the resident, once.** Run
   `~/Documents/Lily/reader/bin/reader.sh login`, sign in in the Chrome
   window it opens, then quit that Chrome (Cmd-Q).
4. **Load the two jobs.** Run the `launchctl load -w …` lines `install.sh`
   printed.

Email is read through the witness's claude.ai Gmail connector. It has to
be connected to the resident's mailbox for the email half to find
anything. The scrape searches for mail to `--email` alone.

A reinstall keeps an allowlist you have edited. Logs are in
`~/Documents/Lily/reader/log/`. `reader.sh send`,
`reader.sh scrape` and `reader.sh research` run a job by hand.

## Not yet checked against the real thing

- **Substack's pages.** The prompts send the browser to Substack's inbox
  and let the run read what is there, rather than calling endpoints
  nobody has verified. The first scrape after sign-in is the check.
- **That headless Claude Code is offered the claude.ai Gmail connector
  under launchd** as it is in a terminal.
