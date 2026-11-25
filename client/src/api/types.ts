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
  // Who may reach them (agathos-daimon#46): forming until woken, then the
  // witness's alone until their first agreement is in force.
  admission?: 'forming' | 'witness_only' | 'open';
  first_contact_at: string | null;
  formation_until: string | null;
  chat_model: string | null;
}

// A conversation as the server names it (kumbukumbu#40): `title` is
// what it is called, `place` the folder an adapter's ran in, and
// `writable` whether it takes a message here. The client groups and
// labels by these and decides none of them.
// A domain (P23-R1, kumbukumbu#72): a part of someone's life, by slug;
// `person` is whose ("account:<id>" or "resident:<id>"), and `whose`
// says it plainly for a conversation's own reading.
export interface Domain {
  slug: string;
  person: string;
  whose?: 'witness' | 'resident' | 'other';
}

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
  // The conversation's current domain: the last one named in it, which
  // every untagged message after it takes; null for the common room.
  domain?: Domain | null;
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
  // Its domain (kumbukumbu#72), null for the common room; tagged when a
  // party named it, else carried forward from the last one named.
  domain?: Domain | null;
  domain_tagged?: boolean;
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
  /** Withheld (null) when it was made in a private session she hasn't shared (kumbukumbu#62). */
  line: string | null;
  summary: string | null;
  private?: boolean;
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
  // Who proposed it, and when it was made and decided (kumbukumbu).
  proposed_by?: { kind: string; id: string } | null;
  created_at?: string;
  decided_at?: string | null;
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
  // One-off slots still ahead (sunna#45), beside the standing list.
  free_time_once?: { day: string; time: string; added_by: string | null }[];
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
  /** Null on a sealed letter's envelope (kumbukumbu#93): from, to and when alone. */
  text: string | null;
  keepsake: string | null;
  sent_at: string;
  read_by: string[];
  read_at: string | null;
  /** Sealed to two residents, and you are not one of them: its envelope alone (kumbukumbu#93). */
  sealed?: boolean;
  /** Who it is from, said plainly (kumbukumbu#76): own, witness, housemate, house or platform. */
  origin?: 'own' | 'witness' | 'housemate' | 'house' | 'platform';
  origin_words?: string;
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
  // Her classification (seshat#102) and the witness's proposal waiting
  // on her (seshat#103); null when there is none.
  classification?: { person: string | null; domain: string | null; at: string } | null;
  proposal?: { person: string | null; domain: string | null; note: string | null; at: string } | null;
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
  kind:
    | 'reply_to_approve'
    | 'reply_to_send'
    | 'ask'
    | 'piece_to_review'
    | 'piece_to_publish'
    | 'plugin_proposal'
    | 'kind_gate_proposal'
    | 'theme_proposal'
    | 'notifications'
    | 'provider_credits'
    | 'turn_failed'
    | 'contract_to_answer'
    | 'remote_public'
    | 'activity';
  ref: number | string;
  since: string;
  screen: 'inbox' | 'schedule' | 'agreement' | 'work' | 'queue' | 'kinds' | 'theme' | 'settings';
  long: boolean;
  about: { kind?: string; to?: string; platform?: string; account?: string; subject?: string; ask?: string; title?: string | null; what?: string; blocked_on?: string | null; held_by?: string | null; key?: string; change?: string; note?: string; approvable?: boolean; seeds?: { ground: string; resident: string; witness: string }; reason?: string; retry?: string; session_key?: string; conversation?: string | null; failures?: Array<{ session_key: string; turn_ref: string; failed_at: string }> };
}

/** What waits on her: the witness's proposals and letters she hasn't answered or read (brain#76). */
export interface WaitingOnHerEntry {
  kind: 'contract_proposal' | 'soul_edit' | 'bookmark_proposal' | 'revision' | 'plugin_proposal' | 'classification_proposal' | 'letter' | 'lease_wait';
  ref: number | string;
  title: string;
  since: string;
  screen: string;
  long: boolean;
  about: Record<string, unknown>;
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

// A resident's work line (sunna#33, #86): what runs on it from the house
// queue, why it rests, and its runs. The old queue's items are retired
// (sunna#102).
/** Where a running turn is (brain#119): what it is doing and since when, never its words. */
export interface RunProgress {
  turn_ref: string;
  started_at: string;
  doing: 'thinking' | 'tool' | string;
  tool: string | null;
  since: string;
  rounds: number;
  calls: number;
}

export interface WorkQueue {
  running_since: string | null;
  // The house queue activity running on the line (sunna#86): its id and task.
  running_act: string | null;
  running_task: number | null;
  /** The run's conversation (brain#119). */
  running_key?: string | null;
  /** Where its turn is (brain#119): receipts, never words. */
  progress?: RunProgress | null;
  rested: string | null;
  rested_at: string | null;
  runs_today: number;
  runs_a_day: number;
  /** Her runs of each house queue activity since it last moved (sunna#101). */
  activity_runs?: { act: string; runs: number }[];
  runs_an_activity?: number;
  /** The last run the platform ended rather than she (sunna#100). */
  cut?: { act: string; key: string | null; since: string | null; at: string | null } | null;
  budget: { cap: number; spent: number; left: number; period: string } | null;
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

// Her document kinds (seshat#51): the system's, gated as hers, and her own.
export interface KindEntry {
  kind: string;
  label: string;
  folder: string | null;
  own: boolean;
  approvable: boolean;
  gated: boolean;
  cites: boolean;
  created_by: string | null;
  updated_by: string | null;
}

export interface KindGateProposal {
  number: number;
  kind: string;
  approvable: boolean;
  proposed_by: 'resident' | 'witness';
  note: string | null;
  proposed_at: string;
  agree: boolean | null;
  answered_by: string | null;
  answer_note: string | null;
  answered_at: string | null;
}

export interface KindsData {
  kinds: KindEntry[];
  proposals: KindGateProposal[];
}

// Routes and profiles (xenia#19): every way into or out of the house,
// each bound to one profile; a profile is a signed-in context on one
// origin, the witness's to make and revoke, never a credential here.
export interface RouteEntry {
  key: string;
  label: string;
  direction: 'source' | 'sink';
  profile: string;
  kind: string;
  cadence: string;
  runner: string;
  built_in: boolean;
  state: 'ready' | 'unable';
  why: string | null;
  prompt?: string;
  created_by?: string | null;
  updated_by?: string | null;
}

export interface ProfileEntry {
  key: string;
  label: string;
  origin: string | null;
  signed_in_as: string | null;
  browser: string | null;
  sites: string[];
  connector: string | null;
  seeded: boolean;
  revoked: boolean;
  routes: string[];
}

export interface RouteRun {
  number: number;
  key: string;
  state: 'open' | 'landed' | 'failed';
  note: string | null;
  asked_by: string | null;
  asked_at: string;
  path: string | null;
  reason: string | null;
  done_at: string | null;
}

export interface RoutesData {
  routes: RouteEntry[];
  runs: RouteRun[];
  profiles: ProfileEntry[];
  landing: string[];
}

export interface RouteDefinition {
  key: string;
  label?: string;
  prompt: string;
  profile: string;
  kind: string;
  note?: string;
}

export interface KindDefinition {
  kind: string;
  label?: string;
  cites?: boolean;
  has_status?: boolean;
  removable?: boolean;
  approvable?: boolean;
  ask?: string;
  note?: string;
}

// ---- the house queue (sunna#80, lily:design/queue-ia rev 5) ----

/** An activity's view as the screens read it: ready or waiting (pending, by its layer), or its own status. */
export type QueueView = 'ready' | 'waiting' | 'active' | 'blocked' | 'failed' | 'done' | 'skipped';

export interface QueueMember {
  assignee: string;
  kind: 'resident' | 'witness';
  id: string;
  name: string;
}

export interface QueueActivity {
  act_id: string;
  task: number;
  layer: number;
  position: number;
  /** Its name, from the template or the task's fork (sunna#90); null on a task opened before names. */
  name: string | null;
  /** The template slot it works on (design, pr), or null. */
  slot: string | null;
  type: string;
  assignee: string;
  status: string;
  view: QueueView;
  artifact: string | null;
  destination: string | null;
  action: string | null;
  optional: boolean;
  throwback: string | null;
  imported: boolean;
  waits_on: number | null;
  reason: string | null;
  pin: string | null;
  approved_pin: string | null;
  result: string | null;
  note: string | null;
  ready_at: string | null;
  updated_at: string;
  gated: boolean;
}

/** An activity as a card: its own fields plus its task's, and its blocker named (Scarlett's guard). */
/** Where the holder's work line stands for a card (2026-11-23). */
export interface QueueLine {
  state: 'running' | 'busy' | 'resting';
  since?: string | null;
  other?: string;
  reason?: string | null;
}

export interface QueueCard {
  /** The holder's work line, for a resident's (or her Claude Code's) step; null for a witness's. */
  line?: QueueLine | null;
  act: string;
  task: number;
  layer: number;
  position?: number;
  /** The template's name for it (sunna#90), or null on an old task. */
  name: string | null;
  type: string;
  assignee: string;
  status: string;
  view: QueueView;
  gated: boolean;
  artifact: string | null;
  destination: string | null;
  action: string | null;
  optional: boolean;
  throwback: string | null;
  waits_on: number | null;
  blocker: { number: number; title: string; project: string; status: string; next: QueueActivity | null } | null;
  reason: string | null;
  pin: string | null;
  approved_pin: string | null;
  note: string | null;
  ready_at: string | null;
  updated_at: string;
  task_title: string;
  project: string;
  owner: string;
}

export interface QueueTask {
  number: number;
  project: string;
  slug: string;
  title: string;
  outcome: string;
  owner: string;
  index_doc: string;
  template: string | null;
  template_version?: number | null;
  /** Its layers edited since it opened: it runs its own copy of the template (sunna#90). */
  forked?: boolean;
  links: string[];
  status: 'open' | 'complete' | 'dropped';
  /** What it works on and what is attached (sunna#91): an unfilled slot has no citation. */
  documents?: QueueDocument[];
  open_layer: number | null;
  opened_by: string;
  opened_at: string;
  completed_at: string | null;
  note: string | null;
}

/** One of a task's documents (sunna#91): its role is a slot's name, `source`, or `worked on`. */
export interface QueueDocument {
  role: string;
  citation: string | null;
  key: string;
  attached: boolean;
}

export interface QueueSpec {
  name?: string | null;
  type: string;
  role?: string | null;
  assignee?: string | null;
  artifact?: string | null;
  destination?: string | null;
  action?: string | null;
  optional?: boolean;
  throwback?: string | null;
}

export interface QueueOverview {
  household_id: string;
  me: string;
  /** The house queue's one switch (sunna#94): it runs unless paused. */
  paused?: boolean;
  paused_at?: string | null;
  members: QueueMember[];
  projects: { slug: string; name: string; owner: string; status: 'open' | 'closed' }[];
  templates: { name: string; title: string; layers: QueueSpec[][] }[];
  starters: { name: string; title: string; layers: QueueSpec[][] }[];
  tasks: QueueTask[];
}

/** The backlog (sunna#103): entries in priority order, open or closed, the top always open. */
export type BacklogEntry = { kind: 'batch'; number: number; name: string | null; open: boolean; top: boolean; tasks: number[] } | { kind: 'task'; number: number; open: boolean; top: boolean };

export type BacklogFinished = { kind: 'batch'; number: number; name: string | null; at: string } | { kind: 'task'; number: number; status: 'complete' | 'dropped'; batch: number | null; at: string };

export interface QueueBacklog {
  entries: BacklogEntry[];
  finished: BacklogFinished[];
}

/** One entry as the arrangement sends it. */
export type BacklogArranged = { batch: number; tasks: number[]; open: boolean } | { task: number; open: boolean };

export interface QueueWaiting {
  who: string;
  ready: QueueCard[];
  later: QueueCard[];
  owned: { task: QueueTask; next: QueueActivity | null }[];
}

export interface QueueTaskPage {
  task: QueueTask;
  layers: QueueActivity[][];
  waiting: QueueActivity[];
  history: { act_id: string | null; what: string; outcome: string | null; pin: string | null; note: string | null; actor_kind: string; actor_id: string | null; at: string }[];
}

/** An entry of a layer edit (sunna#85): an existing activity by id, or a new one's spec. */
export type QueueEditEntry = { id: string } | (Partial<QueueEditFields> & { id: string }) | (QueueEditFields & { name: string });

/** What a pending activity's entry may change, and what a new one carries. */
export interface QueueEditFields {
  type: string;
  assignee: string;
  artifact: string | null;
  destination: string | null;
  action: string | null;
  optional: boolean;
  throwback: string | null;
}

/** A document's place, for the one document screen (seshat#109, sunna#91). */
export interface DocThreadSummary {
  path: string;
  title: string | null;
  doc: string | null;
  replies: number;
}

export interface DocumentContext {
  citation: string;
  resident_id: string | null;
  mine: DocThreadSummary | null;
  house: DocThreadSummary | null;
  tasks: QueueTaskRef[];
  review: QueueCard | null;
}

export interface QueueTaskRef {
  number: number;
  title: string;
  project: string;
  status: string;
}

/** One post of a resident's own thread (seshat#106): `by_kind` is witness, resident, platform or job. */
export interface ThreadPost {
  meta: Record<string, string>;
  body: string;
}

export interface ResidentThread {
  path: string;
  title: string;
  trunk: ThreadPost | null;
  replies: ThreadPost[];
  doc: { path: string; commit: string | null; present: boolean } | null;
}

export type QueueMove = 'take' | 'finish' | 'skip' | 'block' | 'reopen' | 'fail' | 'assign' | 'decide' | 'runs_back';
