# Oneiroi for Claude Code

A Claude Code plugin that makes a Claude Code session a resident's brain
(spec §8, F52). Her identity files and your agreement are given to the
session when it starts; each message you send starts a turn on Oneiroi,
which hands back that turn's context (her bookmark index, how she acts,
what she promised, the madeleine, the dates, figures, journal and
Honcho's view) assembled against your words; her memory tools are
Oneiroi's MCP server; and each turn, your words and her reply, is
captured into her transcripts on Oneiroi.

The main path is Claude Code running on your own machine under Remote
Control, driven from the Claude app on your phone. It is a real Claude
Code session in the folder you enable the plugin in, so the plugin's
hooks and MCP server are the ones it runs.

The plugin is off by default (`defaultEnabled: false`): installing it
does not make every folder hers. You enable it in the one folder where
you talk with her.

## What you need

- A machine with Claude Code, `bash`, `curl` and `jq`, signed in to
  claude.ai (`claude`, then `/login`). Remote Control needs a Pro, Max,
  Ultra, Team or Enterprise plan; API keys are not supported for it
  (Claude Code's Remote Control docs).
- A folder for her sessions. An empty one keeps her apart from your code.
- From Oneiroi: the platform's URL (`https://oneiroi.onrender.com`
  unless yours is elsewhere), her resident id (in the address of any of
  her pages), and an adapter token. Register the adapter as her witness
  with `POST /v1/residents/:id/adapters` and
  `{"adapter": "claude-code", "role": "brain"}` (the client has no screen
  for it yet); the token is shown once, and registering the same name
  again rotates it.

## Install and enable it in one folder

In the folder, start Claude Code and trust the folder when asked:

```sh
cd ~/resident && claude
```

Then, in the session:

```text
/plugin install oneiroi --marketplace SwaggerAllen/Oneiroi
```

That adds this repository as the `oneiroi` marketplace and opens the
plugin's details (Claude Code 2.1.275 or later; on an older one, run
`/plugin marketplace add SwaggerAllen/Oneiroi` and then
`/plugin install oneiroi@oneiroi`). While the repository is private,
Claude Code clones it with the git credentials already on your machine
and never prompts for them (its install docs: `gh auth login`, a
credential helper, or an SSH key that works without a passphrase).

Choose **Install for you, in this repo only (local scope)**. Claude Code
asks for the plugin's options: the Oneiroi URL, her resident id and the
adapter token (masked). Because the plugin starts off, enable it if the
summary says it is disabled: on the **Installed** tab of `/plugin`,
select it and press Space, or from your shell in the folder:

```sh
claude plugin enable oneiroi@oneiroi --scope local
```

Local scope writes `"oneiroi@oneiroi": true` under `enabledPlugins` in
the folder's `.claude/settings.local.json`, which Claude Code keeps out
of git. The options go to your user settings (`pluginConfigs`), and the
token to Claude Code's secure credential store (the macOS Keychain, or
`~/.claude/.credentials.json` where there is none), never to a settings
file. `/plugin configure oneiroi@oneiroi` changes them later.

Quit the session (`/exit`) once it is enabled.

From a shell instead, for a script or a second machine:
`sdk/claude-code/install.sh <folder> <resident-id> [<url>]` does the
same with `claude plugin` commands, taking the token from
`ONEIROI_TOKEN` or asking for it without echo and handing it to
`claude plugin configure --values-stdin`, so it is never on a command
line. It adds the marketplace from the checkout it runs in, or from
`ONEIROI_MARKETPLACE` (e.g. `SwaggerAllen/Oneiroi`).

## Run it from your phone

```sh
cd ~/resident && claude remote-control --spawn session
```

The first time, Claude Code asks you to enable Remote Control; answer
yes. Open the session from the Claude app on your phone (its session
list, or the QR code the command shows on the spacebar). Starting
`claude` in the folder and typing `/remote-control`, or the Desktop
app's Code tab, work too.

`--spawn session` serves one session. Remote Control's default serves
several from one folder, and the platform attributes a memory tool's
call to the newest open turn of the adapter (kumbukumbu #26), so two
sessions talking at once could bookmark on each other's turns.

## Check it worked

1. Send a message. On Oneiroi, Chat's transcripts list a new
   conversation with your words and her reply.
2. Open the reply's "drew on N things": the prompt, her identity files,
   the agreement, `runtime` (how the platform's words read in Claude
   Code), the index with its near-misses, and whatever else the turn was
   given. That list is exactly what was handed to Claude Code.
3. Ask her to bookmark something. The bookmark appears on Memory,
   anchored on that turn. In `/mcp` the server is `plugin:oneiroi:oneiroi`,
   and its tools are named `mcp__plugin_oneiroi_oneiroi__<tool>`, which
   the context tells her.

If a message says Oneiroi did not answer, the turn went ahead without
her context; your words are kept on your machine and captured when the
platform answers again.

## Two residents on one machine

Not in one Claude Code configuration. Enabling is per folder, but a
plugin's options are per user: Claude Code reads `pluginConfigs` from
user and managed settings only and ignores project and local entries,
"because it substitutes these values into plugin hook, MCP, and LSP
configurations, and a cloned repository must not be able to supply
them" (its settings reference). One user's `oneiroi` plugin therefore
speaks for one resident with one token, in every folder it is enabled
in.

The smallest workable way to a second is a second Claude Code
configuration directory: Claude Code keeps settings, session history
and plugins in `CLAUDE_CONFIG_DIR` when it is set (its settings docs).
Run every command for the second resident with it set, and sign in
there once:

```sh
cd ~/second && CLAUDE_CONFIG_DIR=~/.claude-second claude
# then /login, and install and enable the plugin as above
cd ~/second && CLAUDE_CONFIG_DIR=~/.claude-second claude remote-control --spawn session
```

Checked on Linux, where a sensitive option is kept in the configuration
directory's `.credentials.json`: the plugin installed, enabled and
configured under one directory stays apart from the other. Whether the
macOS Keychain entry is kept apart the same way is not documented and
not checked.

## What each hook does

| Hook | Script | Does |
| --- | --- | --- |
| SessionStart, eight of them | `scripts/session-start.sh PART 8` | Prints part PART of the session prefix: the prompt, her identity files, the agreement, and `runtime`. Claude Code takes at most 10,000 characters from one hook and turns the rest into a file path with a preview (its hook docs), so the platform cuts the prefix into numbered parts, one per hook; a part past the end prints nothing, and past the eighth the rest is named as left out. On `startup`, `clear`, `compact` and `fork` it prints; on `resume` it prints nothing, because the prefix is in the resumed conversation (Claude Code replays injected text), and anything in it that changed since rides your next message. |
| UserPromptSubmit | `scripts/turn-start.sh` | Keeps your words, starts the turn on Oneiroi with them, and prints the turn's context, which Claude Code adds beside your message. Sections that would take it past 9,000 characters are left out whole and named. Opens her session on Oneiroi on the first message. A previous message whose Stop never came (an interrupt) is captured with your words alone. |
| Stop | `scripts/capture.sh` | Captures your words and `last_assistant_message`, the reply's final text, with the turn's ref and the platform's start instant. Spooled first and delivered with anything spooled before it; capture is idempotent, so a turn sent twice is stored once. A refusal other than an outage moves the turn to `spool/rejected/` so it does not hold back the rest. |

With the options unset every hook does nothing at all, and prints
nothing.

The context comes in two halves because Claude Code keeps every text a
hook gives it: the prefix once a session, the per-turn part each
message. Each per-turn part stays in the conversation until Claude Code
compacts it, a cost per message (about the index's size and what rides
with it) that the platform's own loop, which replaces its context each
turn, does not pay. Not measured.

Every hook exits 0: on UserPromptSubmit an exit of 2 blocks your
message, and on Stop it keeps Claude going.

Tool calls between your message and the reply are not captured as
messages: they would have to come from the transcript file, which
Claude Code's docs say may lag the hook. Her memory tools' calls reach
Oneiroi through the MCP server anyway, as the bookmarks, tags and the
rest they make; Claude Code's own tools (files, the shell) are not the
platform's.

## Where things are kept

The hooks read the options Claude Code exports to them
(`CLAUDE_PLUGIN_OPTION_URL`, `_RESIDENT`, `_TOKEN`) and nothing else:
no env file, which would put the token on disk in plain text. The token
never goes on a command line, into a URL or into any output: curl reads
it from a config on its stdin.

State lives in the plugin's data directory, `~/.claude/plugins/data/oneiroi-oneiroi/`,
which survives plugin updates: per Claude Code session, the platform
session's key, the turn in flight and your words until they are
captured, and the digest of the prefix the session holds; `spool/`
holds turns not yet delivered. Uninstalling the plugin deletes it
unless you pass `--keep-data`.

## Fixtures, and recording real ones

`fixtures/` holds a payload for each hook, copied from the examples in
Claude Code's hook docs and labelled in each file as "from Claude Code's
docs, not yet recorded from a session" (conventions §9: a hand-written
fixture is a claim about the real system). The core's
`OneiroiWeb.ClaudeCodeHooksTest` runs the plugin's hooks with them
against the real endpoint.

To replace them with real ones, set the plugin's **Record hook payloads
to** option to a folder (`/plugin configure oneiroi@oneiroi`) before
your first session. Each hook then copies its raw stdin, Claude Code's
payload, there as `<event>-<time>-<pid>.json`; SessionStart records
once, not eight times. The payload never holds the token, but it does
hold your words, her reply and local paths: replace those with neutral
text before committing a recording as `fixtures/session_start.json`,
`user_prompt_submit.json` or `stop.json`, change its `_fixture` line to
say when and from what version it was recorded, run the core's suite,
and clear the option again.

## Updating

A marketplace added from GitHub does not auto-update by default (Claude
Code's install docs): `claude plugin update oneiroi@oneiroi`, or turn
auto-update on for the marketplace on `/plugin`'s **Marketplaces** tab.
A marketplace added from a local checkout loads the plugin in place, so
a pull is the update.

## Not yet checked against a real session

- The payload shapes, until a recording replaces the fixtures.
- That Claude Code treats each of the eight SessionStart hooks' plain
  stdout as context, and in which order it presents them (each part
  says its number).
- That Claude adopts the identity it is given this way: Claude Code's
  docs warn that context phrased as out-of-band instructions can be
  surfaced to you as a suspected injection rather than used.
- The character count against Claude Code's limit (the hooks ask for
  9,000 to leave room for JavaScript counting some characters twice).
- That `${user_config.url}` in the MCP server's URL is substituted
  before Claude Code checks the URL at load (`claude plugin validate`
  passes it).

Wake (interface 3) lands with the hands phase.
