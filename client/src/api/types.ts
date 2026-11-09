// The shapes the JSON surface answers with (spec §2), written by hand
// against the routes of OneiroiWeb. The OpenAPI document the server
// serves at /v1/openapi.json types its bodies as bare objects and arrays
// today, so a generated client would type everything `unknown`; these
// are the claim a generated client replaces once the document carries
// schemas (spec §6.15, open for the author).

export type ActorKind = 'witness' | 'resident' | 'judge' | 'hands' | 'job' | 'platform';

export interface Actor {
  kind: ActorKind | string;
  id: string | null;
  model: string | null;
}

export interface Resident {
  id: string;
  slug: string;
  name: string;
  state: string;
  first_contact_at: string | null;
  formation_until: string | null;
  chat_model: string | null;
}

// A conversation as the server names it (kumbukumbu#40): `title` is
// what it is called, `place` the folder an adapter's ran in, and
// `writable` whether it takes a message here. The client groups and
// labels by these and decides none of them.
export interface Session {
  key: string;
  resident_id: string;
  kind: string;
  adapter: string | null;
  title: string;
  place: string | null;
  writable: boolean;
  turns: number;
  opened_at: string;
  last_turn_at: string | null;
  summary: string | null;
}

// What retrieval did with one target (kumbukumbu#43): the target in
// citation form, how often it was considered, returned and used, and
// when last returned and used. The resident reads the same numbers.
export interface RetrievalCount {
  target: string;
  considered: number;
  returned: number;
  used: number;
  // Loaded every turn and never chosen (kumbukumbu#52): not a miss.
  carried?: number;
  last_returned_at: string | null;
  last_used_at: string | null;
}

// A transcript, with each turn's count for "drew on N things".
export interface Transcript {
  session: Session;
  messages: Message[];
  drew_on: Record<string, number>;
}

export interface Message {
  // `sequence:position`, the message's place in its session: what a page
  // of the transcript reads back from. Absent on a turn's own messages.
  cursor?: string;
  session_key: string;
  turn_ref: string;
  role: 'user' | 'assistant' | 'system' | 'tool' | string;
  content: string;
  sent_at: string;
  // True when the record holds no instant of its own for this message
  // (an import's untimed node, kumbukumbu#50): `sent_at` is then the one
  // before it, a stand-in, and is never shown as a time.
  instant_inferred?: boolean;
  actor: Actor;
  refusal: boolean;
}

export interface Injection {
  label: string;
  tokens: number;
  reason: string;
  position: number;
  text: string | null;
}

// What the index holds now (kumbukumbu#38): the numbers listed, in the
// index's order, and the server's own words for the rule. The client
// renders these and restates nothing of how the index is built.
export interface IndexNow {
  listed: number[];
  left_out: number;
  elsewhere: number;
  description: string;
}

// One section of the next turn's preview (brain#41), decided and worded
// by the server: `text` is null where the words are withheld or there
// are none, and `note` says where else they are read, or why not.
export interface PreviewSection {
  label: string;
  tokens: number;
  reason: string;
  text: string | null;
  shown: boolean;
  run: boolean;
  note: string;
}

export interface ContextPreview {
  description: string;
  compacts_first: boolean;
  sections: PreviewSection[];
}

export interface Turn {
  turn_ref: string;
  messages: Array<{ role: string; content: string; sent_at: string; actor: Actor; refusal: boolean }>;
  drew_on: number;
  stopped?: { kind: string; meaning: string; remedy: string };
}

export interface Bookmark {
  number: number;
  line: string;
  summary: string | null;
  session_key: string;
  anchor_ref: string;
  anchor_at: string;
  turns_back: number;
  tags: string[];
  added_by: Actor;
  proposed_by: { kind: string; id: string } | null;
  pinned_by: { kind: string; id: string } | null;
  pinned_at: string | null;
  last_indexed_at: string | null;
}

export interface Tag {
  slug: string;
  state: 'proposed' | 'active' | 'retired' | 'rejected' | string;
  note: string | null;
}

export interface KeyStatus {
  present: boolean;
  stored_at: string | null;
}

export interface BudgetLine {
  purpose: string;
  period: 'day' | 'week' | 'month' | string;
  cap: string | null;
  spent: string;
  exceeded: boolean;
}

export interface SpendRow {
  key: string;
  calls: number;
  cost: string;
}

export interface Ledger {
  key: KeyStatus;
  purposes: string[];
  budgets: BudgetLine[];
  spend: {
    since: string;
    by_purpose: SpendRow[];
    by_model: SpendRow[];
    by_actor: SpendRow[];
  };
}

// The error envelope: what went wrong in words (`meaning`), what to do
// (`remedy`), and the reference that leads to the line that said so
// (`site`) and to the request's log lines (`request_id`), conventions §8.
export interface ApiError {
  kind: string;
  meaning: string;
  remedy?: string;
  site?: string;
  request_id?: string;
}

// Regression (spec §6.4, F42): tests are three texts; a run is models x
// trials answered in the background (eunomia#30); a card is blind, its
// model null until every card of its trial is graded.
export interface RegressionTest {
  number: number;
  prompt: string;
  passes_if: string;
  fails_if: string;
  written_at: string;
  changed_at: string | null;
}

export type TestTexts = Pick<RegressionTest, 'prompt' | 'passes_if' | 'fails_if'>;

export type RunState = 'running' | 'finished' | 'failed';

export interface RegressionRun {
  ref: string;
  models: string[];
  tests: number[];
  behaviours: number[];
  commitments: number[];
  started_at: string;
  finished_at: string | null;
  failed_at: string | null;
  failure: string | null;
  state: RunState;
  cards: number;
}

export type Grade = 'pass' | 'fail';

// One tool call of a trial's turn, in order (eunomia#31): a read ran
// against the resident's records, a mocked call was answered as on
// success and never run. `result` is what the model was given back, cut
// at the server's bound when `truncated`. Blind with its card: while
// `model` is null, the run's model names in it are replaced.
export interface TraceStep {
  tool: string;
  arguments: string;
  kind: 'read' | 'mocked';
  result: string;
  truncated: boolean;
}

export interface RegressionCard {
  card_ref: string;
  test_number: number | null;
  behaviour_number: number | null;
  commitment_number: number | null;
  content: string | null;
  refusal: boolean;
  failure: string | null;
  grade: Grade | null;
  favourite: boolean;
  model: string | null;
  // Empty for a card that called no tool, failed, or was recorded before
  // traces were kept.
  trace: TraceStep[];
}

export interface RegressionResult {
  model: string;
  graded: number;
  passed: number;
  pass_rate: number;
  favourites: number;
  fidelity: { facts: number | null; voice: number | null; commitments: number | null };
}

export interface RegressionRunDetail {
  run: RegressionRun;
  cards: RegressionCard[];
  results: RegressionResult[];
}

// What the run's channel pushes when the run ends.
export interface RunEnd {
  state: Exclude<RunState, 'running'>;
  cards: number;
}

// The schedule route's today (sunna, spec §6.7): every time is HH:MM in
// the resident's zone.
export interface ScheduleCheckin {
  key: string;
  label: string;
  time: string;
  // What its note carries (sunna#28): the catalog's keys checked, and
  // the witness's own words.
  parts: string[];
  prompt: string | null;
  last_day: string | null;
  last_outcome: string | null;
  last_at: string | null;
}

export interface ScheduleFiring {
  key: string;
  day: string;
  outcome: string;
  at: string;
  until: string | null;
}

export interface ScheduleDate {
  number: number;
  title: string;
  on: string;
  kind: string;
  days_to: number;
}

// One free-time slot and what it did today: "ran", "failed: <kind>", or
// null when it has not come yet (sunna#22).
export interface FreeTimeSlot {
  time: string;
  today: string | null;
}

// One free-time run remembered (brain#53, sunna#25), newest first: its
// day and slot ("HH:MM" in the resident's zone, null when it ran off a
// slot), "ran" or "failed: <reason>", its turns, and the receipts of
// what it made, the platform's words and never hers. Free time is
// private as to its words, so its conversation is named and not opened.
export interface FreeTimeRun {
  day: string;
  slot: string | null;
  outcome: string;
  session_key: string | null;
  at: string;
  turns: number;
  did: { tool: string; result: string }[];
}

export interface ScheduleToday {
  day: string;
  now: string;
  timezone: string;
  checkins: ScheduleCheckin[];
  firings: ScheduleFiring[];
  last: { label: string; time: string; at: string } | null;
  next: { label: string; time: string; tomorrow: boolean } | null;
  free_times: FreeTimeSlot[];
  free_time_last: { day: string; outcome: string } | null;
  quiet: { from: string; to: string } | null;
  // Her thinking rounds (sunna#29, #30): the cadence and window in effect,
  // whether each is her own or the default, how many today, and when the
  // last one started. Never their times or what they did.
  rounds?: {
    every_hours: number;
    every_default: boolean;
    waking: string | null;
    waking_default: boolean;
    waking_from_quiet: boolean;
    today: number;
    last_at: string | null;
  };
  dates: ScheduleDate[];
  // What a check-in's note can carry, in the note's order (sunna#28).
  checkin_parts: CheckinPart[];
}

export interface CheckinPart {
  key: string;
  label: string;
  about: string;
}

// A house letter (kumbukumbu#44): the work log between Lily's
// conversations, addressed by name; `read_by` names the conversations
// that read it.
export interface HouseLetter {
  number: number;
  from: string;
  to: string;
  in_reply_to: number | null;
  text: string;
  keepsake: string | null;
  sent_at: string;
  read_by: string[];
  read_at: string | null;
}

// Correspondence (xenia, spec §6.6): a third party's message; a blocked
// sender's keeps no name, subject or words.
export interface CorrespondenceMessage {
  number: number;
  platform: string;
  account: string;
  external_id: string;
  sender: string;
  sender_name: string | null;
  verified: boolean;
  thread: string | null;
  subject: string | null;
  text: string | null;
  sent_at: string;
  received_at: string;
  state: 'received' | 'blocked';
  read_at: string | null;
}

// A blocked identity, and which party blocked it: only that party lifts it.
export interface Block {
  platform: string;
  identity: string;
  name: string | null;
  note: string;
  blocked_by: 'resident' | 'witness';
  blocked_at: string;
}

export interface Reply {
  number: number;
  in_reply_to: number | null;
  platform: string;
  account: string;
  thread: string | null;
  to: string;
  text: string;
  state: 'drafted' | 'approved' | 'declined' | 'sent' | 'superseded';
  note: string | null;
  drafted_at: string;
  decided_at: string | null;
  sent_at: string | null;
  sent_by: string | null;
  url: string | null;
  // The newer draft that replaced this one (xenia#17).
  superseded_by?: number | null;
}

// A document the library holds (seshat): its path says its kind.
export interface LibraryDocument {
  path: string;
  kind: string;
  title: string | null;
  status: string | null;
  bytes: number | null;
  versions: number;
  written_at: string | null;
  // When it first came into the library (seshat#48).
  created_at?: string | null;
  written_by: string | null;
  missing_at: string | null;
  // Why a keepsake mattered, in the resident's words (seshat#32).
  note: string | null;
}

// A document kind as the shelf shows it (seshat#35): its name and its
// place, the server's.
export interface ShelfKind {
  kind: string;
  label: string;
  position: number;
}

export interface LibraryIndex {
  kinds: ShelfKind[];
  documents: LibraryDocument[];
  unadopted: string[];
}

// An adapter registered for the resident (spec §8): a runtime that speaks
// for her (`brain`) or her hands (`reader`, `worker`).
export interface Adapter {
  adapter: string;
  role: string;
  registered_at: string;
  revoked_at: string | null;
}

// The reader's two allowlists (xenia#16): the origins its browser may
// reach when reading correspondence (`scrape`) and when researching
// (`research`), each an origin (scheme, host, optional port) or `*` for
// any site. `set_at` is null until the witness first sets them.
export interface ReaderSites {
  scrape: string[];
  research: string[];
  set_at: string | null;
}

export type ResearchStatus = 'open' | 'answered' | 'failed';

// A research question put to the reader (seshat#38): its notes land in
// the library at `<path>/task.md`; a failed one says why in `reason`.
export interface ResearchQuestion {
  number: number;
  question: string;
  urls: string[];
  sources: string[];
  asked_by: 'resident' | 'witness' | string;
  status: ResearchStatus | string;
  path: string | null;
  reason: string | null;
  asked_at: string;
  settled_at: string | null;
}

// A passage the library's search found nearest a query (seshat): the
// document it is in and the words.
export interface LibraryHit {
  path: string;
  kind: string;
  title: string | null;
  text: string;
  distance: number;
}

// An ask of the witness (agathos-daimon#35): a tool she lacked, or leave
// for an act, and the answer.
// One entry of what waits on the witness (spec §5 `needs_you`, brain#65):
// oldest first from the server, each naming the screen it is decided on.
// It only shows; `long` is a mark past two days, and nothing more.
export interface NeedsYouEntry {
  kind: 'reply_to_approve' | 'reply_to_send' | 'ask' | 'piece_to_review' | 'piece_to_publish' | 'work_blocked' | 'plugin_proposal';
  ref: number | string;
  since: string;
  screen: 'inbox' | 'schedule' | 'agreement' | 'work';
  long: boolean;
  about: { kind?: string; to?: string; platform?: string; account?: string; subject?: string; ask?: string; title?: string | null; what?: string; blocked_on?: string | null; key?: string; change?: string; note?: string };
}

export interface Ask {
  number: number;
  kind: 'tool' | 'act';
  subject: string;
  why: string;
  asked_at: string;
  decision: 'approve' | 'decline' | 'noted' | null;
  note: string | null;
  answered_at: string | null;
}

// The writing gate (seshat#42).
export interface Pieces {
  for_review: { path: string; title: string | null; written_at: string | null; last: { state: string; note: string | null; decided_at: string } | null }[];
  approved: { path: string; title: string | null; state: string; note: string | null; draft_url: string | null; decided_at: string }[];
  drafted: { path: string; title: string | null; state: string; note: string | null; draft_url: string | null; decided_at: string }[];
}

// A platform report (gaia#20).
export interface FeedbackReport {
  number: number;
  kind: 'bug' | 'feature_request';
  surface: string | null;
  body: string;
  trace_id: string | null;
  author_kind: string;
  status: string;
  note: string | null;
  filed_at: string;
}

// The work queue (sunna#33): long items in priority order, either
// party's, and the loop that runs them one at a time.
export interface WorkItem {
  number: number;
  what: string;
  done_when: string;
  status: 'open' | 'in_work' | 'blocked' | 'done' | 'dropped' | string;
  blocked_on: string | null;
  position: number;
  added_by: string;
  added_at: string;
  note: string | null;
  moved_by: string | null;
  moved_at: string | null;
  shipped: string | null;
  slipped: string | null;
  why: string | null;
  wrapped_at: string | null;
  runs: number;
  session_key: string | null;
}

export interface WorkQueue {
  items: WorkItem[];
  running: number | null;
  running_since: string | null;
  rested: string | null;
  rested_at: string | null;
  runs_today: number;
  runs_a_day: number;
  budget: { cap: number; spent: number; left: number; period: string } | null;
  // Armed by her for a batch, off once the queue clears (sunna#35).
  armed: boolean;
  armed_at?: string | null;
  // Who armed it (sunna#43): her tool, or his button.
  armed_by?: 'resident' | 'witness' | null;
}

// A plugin, as the agreement shows it (brain#68, agathos-daimon#37):
// every memory slot is one, contract material.
export interface PluginEntry {
  key: string;
  name: string;
  about: string;
  tier: 'first_party' | 'installable';
  place: string;
  reads: string[];
  installed: boolean;
  on: boolean;
  carried_over: boolean;
  changed_by: string | null;
  changed_at: string | null;
  // An installable plugin's (brain#68): who wrote it, and the catalog's digest now.
  author?: string;
  digest?: string;
  // Its audit, once installed: the copies checked against the lockfile by
  // content, a newer catalog version, and how often it was in her context.
  audit?: { files: number; pinned: string | null; verified: boolean; update: boolean; shown: number; last_shown: string | null };
}

export interface PluginProposal {
  number: number;
  key: string;
  change: 'install' | 'remove' | 'on' | 'off';
  proposed_by: 'resident' | 'witness';
  note: string | null;
  proposed_at: string;
  agreed: boolean | null;
  answer_note: string | null;
  answered_at: string | null;
}

export interface PluginsData {
  plugins: PluginEntry[];
  proposals: PluginProposal[];
}
