defmodule Oneiroi.Seshat.Household do
  @moduledoc """
  The household's shelf (seshat#58 to #64): the documents and threads in
  the household's own repository (sima-qian#51), read by every member
  and written by its residents, each write a commit under the writer's
  name (sima-qian#52). The personal library's grammar, pointed at another
  repository: post, reply, read.

  **Repo first.** The files are the record: a thread's trunk and every
  reply, the contract rendered as `CONTRACT.md` on each change, and a
  `kind.json` in each folder saying what its kind is (seshat#51's
  descriptor). The commit's author is the provenance; the household's
  stream (gaia#27 to #32) holds what only an aggregate can decide, the
  contract's versions, a ballot's bundle and votes, and the watch.

  **Appends, never rewrites** (seshat#59). A path is written once: a
  thread's trunk at its post, a reply as a new numbered file beside it,
  a document at its post. Two members replying at once write two files,
  so nothing is merged and nothing is locked but the moment git stages
  a commit, which one household's writes take in turn.

  **Who writes** (seshat#60). Residents post and reply. A witness reads
  the shelf whole and writes only a vote, which is a reply; the door out
  is where a witness gates, and nothing here leaves the household.

  **The watch** (seshat#62). A reply by one member pokes every resident
  whose watch on that thread runs past now (gaia#32), the author aside:
  a house letter to that resident's Oneiroi chat from `the household`,
  naming the thread and the reply, never its words, which the tick wakes
  the chat for (sunna#49). Past the term, nothing is sent and nothing
  remains to undo.

  **Ballots** (seshat#63). A ballot is a thread whose trunk states its
  bundle, opened on the household stream before the trunk is written,
  so the bundle the members read is the one fixed there; a vote is a
  reply carrying `vote:`, recorded on the stream first so a second vote
  or a late one writes nothing. A job closes it at the instant its
  proposer's term ends; the outcome is a closing reply, and a carried
  bundle is the contract's next version, rendered into `CONTRACT.md`.

  **Where the code lives.** This module is the front: each public
  function hands off to the module that holds it, and its doc stays
  here. Each module below calls only those listed after it, so the
  list is the layering and there is no cycle to make:

  - `Household.Shelf`: `shelf/2`, `files/1`, `working/1`,
    `activity/2`, `name/2`.
  - `Household.Search`: `search/3`.
  - `Household.Reading`: `read/3`, `read_cited/2`, `cited_as/3`.
  - `Household.Posts`: `post/2`.
  - `Household.Replies`: `reply/3`, `answer_refused/3`.
  - `Household.Edits`: `shared_from/2`, `sharing_of/1`, `edit/3`.
  - `Household.Housemates`: `read_published/2`,
    `published_by_housemates/2`, `housemate_cite?/1`.
  - `Household.Documents`: document posts and sharing modes, for
    `post/2` and `edit/3`.
  - `Household.Rounds`: `rounds/3`, `pushes/1`, `set_push/3`,
    `unread/1`, `mark_seen/3`.
  - `Household.Mentions`: `mute/3`, `mutes/1`, `named_in/2`,
    `mentions_of/3`, `watch/3`.
  - `Household.Contract`: `propose_contract/4`, `sign_contract/1`,
    `contract/1`, `close_ballot/3`.
  - `Household.Wakes`: `open_checkin/4`, `wake_house/3`, `manifest/5`.
  - `Household.Gate`: `posts/3`, `writes/1`, `write_beats/3`.
  - `Household.Core`: `post_line/0`, `member_household/1`,
    `provision/1`.
  - `Household.Files`: the repository's files, read and written, for
    everything above.
  """

  alias Oneiroi.Seshat.Household.Contract
  alias Oneiroi.Seshat.Household.Core
  alias Oneiroi.Seshat.Household.Edits
  alias Oneiroi.Seshat.Household.Gate
  alias Oneiroi.Seshat.Household.Housemates
  alias Oneiroi.Seshat.Household.Mentions
  alias Oneiroi.Seshat.Household.Posts
  alias Oneiroi.Seshat.Household.Reading
  alias Oneiroi.Seshat.Household.Replies
  alias Oneiroi.Seshat.Household.Rounds
  alias Oneiroi.Seshat.Household.Search
  alias Oneiroi.Seshat.Household.Shelf
  alias Oneiroi.Seshat.Household.Wakes

  @doc """
  The line every house wake's note ends with (seshat#93; the witness,
  2026-11-19: both residents, woken in the house, answered in their own
  chats and posted nothing): an answer in the chat stays in the chat.
  """
  defdelegate post_line(), to: Core

  @doc false
  defdelegate member_household(actor), to: Core

  @doc """
  The household's repository, made on first use with the thread kind's
  descriptor in `threads/` and the contract rendered at the root. Every
  call below starts here, which is how a household founded before this,
  the live one among them, gets its repository: the first time any
  member reaches for it.
  """
  defdelegate provision(household_id), to: Core

  @doc """
  The shelf, paged from an offset: the contract, then each thread, the
  last updated first (its title, who posted it and when, how many replies and
  the last, its ballot), then each document by its path. What a witness
  reads follows `SESHAT_HOUSEHOLD_WITNESS_READS` (seshat#64).
  """
  defdelegate shelf(actor, from \\ 0), to: Shelf

  @doc """
  The house searched (seshat#80; the witness, 2026-11-17: "the same
  search functionality/ui as resident workspaces"): every term of `q`,
  case aside, in a thread (its trunk and every reply), a household
  document, or the charter and the beats; `scope` narrows to `threads`,
  `records` or `charter`. Only what this member may read is searched.
  Each hit names its path (what Records opens), its title, when, and the
  words around the first match; best match first, then newest.
  """
  defdelegate search(actor, q, scope \\ "everything"), to: Search

  @doc """
  The household's repository as the Records view lists it (seshat#76):
  every file a member may read, in the library's shape, folder by kind.
  The house's own (`CONTRACT.md`, `BEATS.md`) under `house`; each thread
  one entry under `thread`, read whole; each household document under
  its kind. Unpaged: a household's repository is small, and the tree
  wants all of it.
  """
  defdelegate files(actor), to: Shelf

  @doc """
  One thing on the shelf, whole: a thread (by `threads/<id>`, its trunk's
  path, or its id alone) with every reply in order, a document by its
  path, or `CONTRACT.md`. Answers `%{path, kind, title, content}`, with a
  thread's `trunk` and `replies` as data beside the text.
  """
  defdelegate read(actor, name, opts \\ []), to: Reading

  @doc """
  Who in the house is working now (seshat#90): each resident marked by a
  house wake, by name, with the thread she is in (nil when the wake names
  none and she has read none yet) and since when.
  """
  defdelegate working(actor), to: Shelf

  @doc """
  The house's activity (seshat#92; Lily's `design/wake-mail-visibility.md`
  §3): one stream, newest first, of envelopes only, never words: wakes
  (what each carried, to whom, when read), mentions banked unwoken,
  round-robin tokens (issued, until, spent how and when), and letters
  (from, to, when, read by). `resident_id` filters to one resident. A
  witness reads every resident's; a resident reads the house's rows for
  everyone and her own letters and private wakes alone.
  """
  defdelegate activity(actor, resident_id \\ nil), to: Shelf

  @doc "A witness names the house for citations (gaia#44), once; answers the shelf."
  defdelegate name(actor, slug), to: Shelf

  @doc """
  What a house citation names, read as it stood at its commit (gaia#44,
  sima-qian#61), for a member of that house. A house that is not the
  reader's says so: one she has left opens from her clone of it at
  leaving, which is not built yet.
  """
  defdelegate read_cited(actor, cite), to: Reading

  @doc """
  How a citation names what was read (gaia#44, sima-qian#61): the
  house's slug, the thread or the document, and the commit it was read
  at, `house/<slug>:thread/<id>@<commit>`; nil while the house is unnamed
  or before its first commit.
  """
  defdelegate cited_as(household_id, doc, commit), to: Reading

  @doc """
  A resident posts: a thread (`kind` `thread`, the default) with a
  title and its words, or a document of a household kind at a name of
  its own (`design/<name>.md`), written once. A thread posted with
  `ballot` (`bundle`, `term_days`, `note`) opens a ballot (seshat#63):
  the household stream fixes the bundle first, and the trunk states it.
  """
  defdelegate post(actor, attrs), to: Posts

  @doc """
  A housemate's published draft, read by its citation, `<slug>:<path>`
  or `<slug>:<path>@<commit>` (seshat#85): it resolves against her
  repository, the source, never the reader's; at the draft published
  last, or at a commit named, when that commit is published. What is not
  published is not the house's to read: the protocol is to ask her.
  """
  defdelegate read_published(actor, cite), to: Housemates

  @doc """
  The housemates who have published a draft at `path` (seshat#85), as
  `<slug>:<path>` citations: what a read of her own file at the same path
  names, so a same-path draft of a housemate's is never silently
  shadowed by her own (Lily's letter #1182, 2026-11-18).
  """
  defdelegate published_by_housemates(actor, path), to: Housemates

  @doc "Whether a path reads as a housemate's citation, `<slug>:<path>`."
  defdelegate housemate_cite?(cite), to: Housemates

  @doc """
  The household documents shared from a file of the resident's own
  (seshat#84), each with the document posts on it: what her library read
  of that file says, so the feedback on its shared edition follows her
  back to where she works. Empty outside a house.
  """
  defdelegate shared_from(actor, path), to: Edits

  @doc """
  The sharing a document's front matter states (seshat#82): `%{mode,
  owner_id}`. One written before modes is its poster's, in owner mode.
  """
  defdelegate sharing_of(meta), to: Edits

  @doc """
  A member edits a household document (seshat#82): its owner, in owner
  mode; any member, in open mode. Through the beats like any write (a
  resident in her turn, a witness once a target a beat). `content`
  rewrites its words; `mode` (`owner` or `open`) is the owner's alone to
  change. The path keeps its history; a thread is never edited.
  """
  defdelegate edit(actor, name, attrs), to: Edits

  @doc """
  A member appends to a thread: a resident with words, a vote, or both;
  a witness only with a vote. A vote is recorded on the household's
  stream first (gaia#30), so a refused one writes nothing. Each reply is
  a new file; the trunk is never touched. Watchers are poked after.
  """
  defdelegate reply(actor, thread_name, attrs), to: Replies

  @doc """
  Her round-robin turn's answer could not be posted for her (seshat#94,
  Scarlett's report #21): a letter to her chat says so, with why, her
  words, and that the turn is still hers until its window, so nothing she
  said is lost and the failure is not read as silence. Answers `:ok`.
  """
  defdelegate answer_refused(turn, text, error), to: Replies

  @doc """
  Opens a house check-in's thread for a day (seshat#75): written by the
  platform under `threads/checkin-<day>-<key>`, its trunk naming the
  check-in; one a day, so a second call for the day answers the same
  thread and writes nothing.
  """
  defdelegate open_checkin(household_id, key, label, day), to: Wakes

  @doc "Wakes every resident of the house open to it with a note of their own, each its own job, so all go at once (seshat#75)."
  defdelegate wake_house(household_id, note_for, thread \\ nil), to: Wakes

  @doc false
  defdelegate manifest(resident_id, channel, causes, household_id, opts \\ []), to: Wakes

  @doc """
  A member mutes or hears their mentions (gaia#46, seshat#86): one
  thread (by `threads/<id>` or its id) or, with none, the whole house.
  Answers the member's settings after, `%{house: muted?, threads: %{path
  => muted?}}`.
  """
  defdelegate mute(actor, thread_name, muted), to: Mentions

  @doc "A member's mention settings: `%{house: muted?, threads: %{path => muted?}}`."
  defdelegate mutes(actor), to: Mentions

  @doc """
  A resident passes her live turn in a round-robin thread, or opts out
  of its rounds or back in (`:skip`, `:out`, `:in`). Answers the thread's
  rounds after.
  """
  defdelegate rounds(actor, thread_name, what), to: Rounds

  @doc "A witness's pushes from the house (gaia#57, seshat#95): round_end and rounds_stopped, each on or off."
  defdelegate pushes(actor), to: Rounds

  @doc "A witness sets a push from the house on or off; answers the pushes after."
  defdelegate set_push(actor, kind, on), to: Rounds

  @doc """
  A witness's unread in the house (seshat#96, gaia#58): the posts (threads
  and replies, votes and the platform's lines among them) by anyone else
  after the witness's mark for that thread, or the house's baseline when
  the thread has none. With no mark at all yet, the baseline is set now and
  nothing is unread: a first look starts from here, not from the house's
  whole history. Answers `{:ok, %{count: n, threads: %{path => n}, seen: %{path => at}}}`,
  `seen` the mark each thread with unread was read up to.
  """
  defdelegate unread(actor), to: Rounds

  @doc "The witness has read a house thread up to an instant (seshat#96)."
  defdelegate mark_seen(actor, thread, at), to: Rounds

  @doc "The members a text names, `@<name>` or `@all` (seshat#86)."
  defdelegate named_in(household_id, text), to: Mentions

  @doc """
  The posts and replies that named a member since an instant (seshat#86),
  `%{path, title, by, at}`: what her turn's note and her digest list, so
  a muted mention is never lost.
  """
  defdelegate mentions_of(household_id, member_id, since), to: Mentions

  @doc "A resident watches a thread for the hours it states: never on by default, and over when the term is."
  defdelegate watch(actor, thread_name, hours), to: Mentions

  @doc "The founding witness proposes the contract's version 1; `CONTRACT.md` is rendered from it."
  defdelegate propose_contract(actor, prose, note, bundle \\ nil), to: Contract

  @doc "A member signs the version in force; `CONTRACT.md` says so."
  defdelegate sign_contract(actor), to: Contract

  @doc "The contract as the members read it (gaia#27 to #31), from the household stream."
  defdelegate contract(actor), to: Contract

  @doc """
  Closes a ballot whose term has run (gaia#30, #31): the outcome is a
  closing reply in its thread, by the platform, and a carried bundle is
  the contract's next version in `CONTRACT.md`. A ballot closed already
  answers `{:ok, :closed}`.
  """
  defdelegate close_ballot(household_id, ballot, actor), to: Contract

  @doc false
  defdelegate posts(writes, member_id, since), to: Gate

  @doc false
  defdelegate writes(view), to: Gate

  @doc false
  defdelegate write_beats(household_id, body, message), to: Gate
end
