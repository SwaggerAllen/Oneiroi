import type { Gift } from '../next/onboarding/gift';
import type {
  CatalogModel,
  Category,
  DisclosureEntry,
  Judging,
  Room,
  SuccessionArchive,
  SuccessionView,
  Uncertainty,
  Adapter,
  DocumentContext,
  QueueCard,
  QueueEditEntry,
  QueueTaskRef,
  ResidentThread,
  QueueMove,
  QueueOverview,
  QueueBacklog,
  BacklogArranged,
  QueueSpec,
  QueueTaskPage,
  QueueWaiting,
  Ask,
  WorkQueue,
  NeedsYouEntry,
  ScheduleDate,
  WaitingOnHerEntry,
  PluginProposal,
  PluginsData,
  KindDefinition,
  KindsData,
  RouteDefinition,
  RoutesData,
  FeedbackReport,
  Pieces,
  ApiError,
  Bookmark,
  ContextPreview,
  Block,
  CorrespondenceMessage,
  FreeTimeRun,
  Grade,
  HouseLetter,
  IndexNow,
  LibraryHit,
  LibraryDocument,
  Message,
  LibraryIndex,
  Injection,
  Ledger,
  ReaderSites,
  RegressionRun,
  RegressionRunDetail,
  RegressionTest,
  Reply,
  ResearchQuestion,
  ResearchStatus,
  Resident,
  RetrievalCount,
  ScheduleToday,
  Session,
  Tag,
  TestTexts,
  Transcript,
  Turn,
} from './types';

// The one door to the server (spec §6.15): every screen's data comes
// through here, with the session cookie and the browser's own Origin,
// which is what the Origin check reads (gaia#5).
export class RequestFailed extends Error {
  readonly status: number;
  readonly error: ApiError | null;

  constructor(status: number, error: ApiError | null) {
    super(error?.meaning ?? `request failed with ${status}`);
    this.status = status;
    this.error = error;
  }
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const response = await fetch(path, {
    method,
    credentials: 'include',
    headers: body === undefined ? {} : { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  // A proxy's error page (Render's 502 is HTML) is not JSON: it must still
  // arrive as a failed request with its status, never as a parse error
  // that reads like a bug and loses the status (brain#45).
  let json: unknown = null;
  try {
    json = text ? (JSON.parse(text) as unknown) : null;
  } catch {
    if (response.ok) throw new RequestFailed(response.status, null);
  }
  if (!response.ok) {
    const error = (json as { error?: ApiError } | null)?.error ?? null;
    throw new RequestFailed(response.status, error);
  }
  return json as T;
}

/** A book in her library (seshat#98): its place and how far she has read. */
/** What a backup remote's host says it is (sima-qian#65). */
export interface RemoteCheck {
  visibility: 'private' | 'public' | 'unknown';
  push: 'yes' | 'no' | 'unknown';
}

/** The words for a remote just set: a public repository is warned of, never refused. */
export const remoteWords = (check: RemoteCheck | undefined, changed: boolean): string =>
  check?.visibility === 'public'
    ? `${changed ? 'Changed' : 'Set'}, but this repository is public: anyone can read her backups. Make it private on its host; backups go on either way.`
    : changed
      ? 'Changed.'
      : 'Set.';

export interface Book {
  slug: string;
  title: string;
  author: string | null;
  rights: string;
  caveat: string | null;
  chapters: number;
  read: number;
  current: string | null;
  read_at: string | null;
  imported_at: string;
}

export interface DocumentVersion {
  version: string;
  act: 'written' | 'adopted' | 'moved' | 'archived' | 'tombstone' | 'committed';
  at: string | null;
  actor: { kind: string; id: string } | null;
  note: string | null;
  bytes: number | null;
  commit: string | null;
  committed_at: string | null;
  current: boolean;
  restorable: boolean;
}

// Presence on Substack (xenia#20).
export interface PresenceAccount {
  key: string;
  name: string | null;
  host: string;
  followed: boolean;
  excluded: boolean;
  excluded_at: string | null;
  reason: string | null;
  first_seen_at: string;
  last_sampled_at: string | null;
}

export interface PresenceRead {
  item: string;
  account: string;
  kind: 'post' | 'note';
  title: string | null;
  url: string;
  published_at: string | null;
  likes: number;
  comments: number;
  restacks: number;
  score: number;
  cut: 'ranked' | 'serendipity';
  excerpt: string | null;
  read_at: string | null;
}

export interface PresenceInteraction {
  number: number;
  pass: number;
  item: string;
  account: string;
  kind: 'like' | 'comment' | 'restack';
  text: string | null;
  supersedes: number | null;
  superseded_by: number | null;
  state: 'staged' | 'revise' | 'approved' | 'passed' | 'sent' | 'failed' | 'superseded';
  comment: string | null;
  release_at: string | null;
  staged_at: string;
  decided_at: string | null;
  sent_at: string | null;
  url: string | null;
  reason: string | null;
  read: PresenceRead | null;
}

export interface PresenceState {
  settings: { enabled: boolean; handle: string | null; set_at: string | null; follows_at: string | null; visible: number | null; cursor: string | null };
  accounts: PresenceAccount[];
  passes: Array<{ number: number; day: string; accounts: string[]; pool: number; ranked: number; serendipity: number; cap: number; drawn_at: string; reads: PresenceRead[] }>;
  interactions: PresenceInteraction[];
}

// House check-ins (gaia#41, seshat#75, sunna#65).
/** A resident's subscription (spec F53, nisaba#23); `started: false` before the first. */
export type SubscriptionState =
  | { started: false }
  | {
      started: true;
      plan: string;
      price: string;
      period_days: number;
      state: 'active' | 'lapsed' | 'cancelled';
      renews_at: string | null;
      lapsed_at: string | null;
      cancelled_at: string | null;
      custody_due_at: string | null;
      paying: boolean;
    };

/** A ballot's bundle: a rule in words, or a setting with its value (gaia#29). */
export type BallotItem = { rule: string } | { setting: string; value: string | number | boolean };

export interface HouseBallotSummary {
  number: number;
  closes_at: string;
  closed_at: string | null;
  passed: boolean | null;
}

export interface HouseThreadSummary {
  kind: 'thread';
  path: string;
  title: string;
  by: string;
  posted_at: string;
  replies: number;
  last_reply_at: string | null;
  ballot: HouseBallotSummary | null;
}

export interface HouseDocument {
  kind: string;
  path: string;
  title: string;
  by: string | null;
  posted_at: string | null;
}

/** A hit in the house's search (seshat#80): Records opens its path. */
export interface HouseHit {
  type: 'thread' | 'document' | 'charter';
  path: string;
  title: string | null;
  at: string | null;
  snippet: string;
}

export interface HouseShelf {
  household_id: string;
  /** Its name for citations (gaia#44), null until a witness names it. */
  slug: string | null;
  contract: string;
  total: number;
  from: number;
  next: number | null;
  threads: HouseThreadSummary[];
  documents: HouseDocument[];
}

export interface HousePost {
  path: string;
  meta: Record<string, string>;
  body: string;
}

export interface HouseDoc {
  path: string;
  kind?: string;
  title: string;
  content: string;
  trunk?: HousePost;
  replies?: HousePost[];
  ballot?: HouseBallot | null;
  /** A document's sharing (seshat#82): owner mode, its owner alone edits; open, everyone. */
  sharing?: { mode: 'owner' | 'open'; owner_id: string | null; owner: string | null };
  /** A document's document posts, where its feedback is (seshat#83). */
  discussed?: { path: string; title: string; replies: number }[];
  /** A document post's document, at its latest draft (seshat#83). */
  doc?: { path: string; commit: string | null; content: string; present: boolean } | null;
}

/** Your mentions in the house (seshat#86): the house muted or heard, and each thread's own. */
export interface HouseMentions {
  house: boolean;
  threads: Record<string, boolean>;
}

export interface HouseVersion {
  version: number;
  prose: string;
  rules: string[];
  settings: Record<string, unknown>;
  bundle: BallotItem[] | null;
  ballot: number | null;
  decided_by: string | null;
  decided_at: string | null;
  note: string | null;
}

export interface HouseMember {
  kind: 'witness' | 'resident';
  id: string;
  name: string;
  joined_at: string;
  signed_version: number | null;
}

export interface HouseBallot {
  number: number;
  thread: string;
  bundle: BallotItem[];
  term_days: number;
  opened_by: string;
  opened_at: string;
  closes_at: string;
  note: string;
  closed_at: string | null;
  passed: boolean | null;
  yes: number;
  no: number;
  members: number;
  votes?: { name: string; vote: string; voted_at: string }[];
}

export interface HouseContract {
  household_id: string;
  in_force: HouseVersion | null;
  versions: HouseVersion[];
  members: HouseMember[];
  ballots: HouseBallot[];
  /** Every setting a ballot can change, with what it means and takes (gaia#49). */
  catalog?: HouseSetting[];
}

export interface HouseSetting {
  key: string;
  label: string;
  about: string;
  default: string | number | boolean | null;
  type: 'integer' | 'choice' | 'boolean';
  min?: number;
  max?: number;
  options?: string[];
}

export interface HouseTurn {
  turn: number;
  resident_id: string;
  name?: string;
  beat_top: string;
  fired_at: string;
  ends_by: string;
  ended_at: string | null;
  outcome: string | null;
}

export interface HouseBeats {
  shape: Record<string, number | boolean | string>;
  now: string;
  beat: { top: string; signup_closes: string; ends: string; turns_fired: number; turns: HouseTurn[] };
  next_top: string;
  open_turn: HouseTurn | null;
  queue: { position: number; resident_id: string; name: string; missed: number; turns_this_beat: number }[];
  /** Who has had her share of the beat running (gaia#51): no longer waiting in it. */
  had_turn?: { resident_id: string; name: string }[];
  upcoming: { top: string; signup_closes: string }[];
  profiles: { kind: string; id: string; name: string; profile: string; missed: number }[];
  closed: { beat_top: string; closed_at: string; turns: { turn: number; resident_id: string; outcome: string | null }[]; passed_over: string[]; carried: string[]; note: string | null }[];
  you: { id?: string; kind: string; profile: string | null; quota: number; quota_left: number; quota_window_hours: number };
  /** How the house talks (gaia#53): the beats, or round-robin threads. */
  conversation?: 'beats' | 'round_robin';
  /** Under round-robin threads, the turns newest first (seshat#89); null under the beats. */
  rounds?: HouseRoundTurn[] | null;
  /** Every thread's rounds (gaia#55): running with its live turn, or stopped; who opted out. */
  round_threads?: HouseRoundThread[];
}

export interface HouseRoundThread {
  thread: string;
  round: number;
  stopped: boolean;
  live: { resident_id: string; name: string | null; until: string } | null;
  /** Who is still in its rounds, by name (the witness, 2026-11-20). */
  opted_in?: string[];
  opted_out: string[];
  changed_at: string;
}

/** One row of the house's activity (seshat#92): envelopes only, never words. */
export type HouseActivity =
  | { kind: 'wake' | 'mention' | 'held'; at: string; resident_id: string; name: string | null; channel: string; causes: Record<string, unknown>[]; delivered: boolean; read_at: string | null; wake_id: string }
  | { kind: 'token'; at: string; resident_id: string; name: string | null; thread: string; round: number; turn_id: string; until: string; outcome: string | null; spent_at: string | null }
  | { kind: 'letter'; at: string; resident_id: string; name: string | null; number: number; from: string; to: string; in_reply_to: number | null; read_by: string[] };

export interface HouseWorking {
  resident_id: string;
  name: string | null;
  /** The thread she is answering, or null when her wake names none and she has read none yet. */
  thread: string | null;
  since: string;
}

export interface HouseRoundTurn {
  turn_id: string;
  thread: string;
  round: number;
  resident_id: string;
  name: string | null;
  issued_at: string;
  expires_at: string;
  outcome: 'posted' | 'skipped' | 'empty' | 'expired' | 'opted_out' | null;
  spent_at: string | null;
}

export interface HouseCheckin {
  key: string;
  label: string;
  time: string;
  last_day: string | null;
  last_thread: string | null;
  last_fired_at: string | null;
  // On a resident's Rhythm page: her own words for it, and her parts (sunna#68).
  prompt?: string | null;
  parts?: string[];
}

export interface HouseCheckins {
  zone: string | null;
  checkins: HouseCheckin[];
}

export interface ResidentRecord extends Resident {
  remote: string | null;
  last_backup: { at: string | null; sequence: number | null; root: string | null; commit: string | null };
}

export interface ChatgptImport {
  conversations: number;
  messages: number;
  context: number;
  gaps: number;
  report_path: string;
}

export interface Report {
  number: number;
  by: string;
  text: string;
  filed_at: string;
  state: string;
  outcome: string | null;
  resolved_at: string | null;
  resolution_note: string | null;
  steps: Array<{ at: string; reason: string }>;
}

export interface ReportLadder {
  reports: Report[];
  strikes: Array<{ number: number; report: number; consequence: string; at: string }>;
}

export interface Lease {
  path: string;
  holder_id: string;
  state: 'held' | 'taken';
  acquired_at: string;
  renewed_at: string;
  takeable_at: string;
  takeable: boolean;
  waiting_at: string | null;
  has_draft: boolean;
  taken_at: string | null;
  kept_at: string | null;
}

export interface ThemeState {
  file: string;
  seeds: { ground: string; resident: string; witness: string };
  source: 'file' | 'default';
  ok: boolean;
  checks: Array<{ name: string; passed: boolean; value: number; needs: number }>;
  proposals: Array<{
    number: number;
    seeds: { ground: string; resident: string; witness: string };
    note: string;
    proposed_at: string;
    agree: boolean | null;
    answered_by: unknown;
    answer_note: string | null;
    answered_at: string | null;
  }>;
}

export interface CalendarDay {
  day: string;
  journal: { plan: number; note: number; todo: number; done: number; wrap: number; unwrapped: boolean } | null;
  story: {
    sessions: Array<{ key: string; kind: string; title: string; locked: boolean; first_at: string; last_at: string; messages: number | null }>;
    scenes: Array<{ number: number; kind: string; corrects: number | null; title: string | null; from_time: string | null; to_time: string | null }>;
    complete: boolean | null;
  };
  schedule: {
    quiet: { from: string; to: string } | null;
    rounds: number;
    entries: Array<{ kind: string; key: string; label: string | null; time: string; at: string; deferred?: boolean; rule: { freq: string } | null; status: string; added_by?: string; date_kind?: string }>;
  } | null;
}

export type SearchResult =
  | { type: 'transcript'; ref: { session_key: string; turn_ref: string; cursor: string }; title: string; snippet: string; at: string | null; score: number | null; domain?: { slug: string; person: string } | null }
  | { type: 'document'; ref: { path: string }; title: string; snippet: string; at: string | null; score: number | null }
  | { type: 'bookmark'; ref: { number: number }; title: string; snippet: string; at: string | null; score: number | null }
  | { type: 'scene'; ref: { day: string; id: string | null; path: string }; title: string; snippet: string; at: string | null; score: number | null }
  | { type: 'letter'; ref: { number: number }; title: string; snippet: string; at: string | null; score: number | null };

export const api = {
  login: (email: string, password: string) =>
    call<{ account_id: string }>('POST', '/v1/session', { email, password }),
  logout: () => call<void>('DELETE', '/v1/session'),
  // The front door from outside (gaia#19): its state, and sign-up behind it.
  door: () => call<{ state: GateState }>('GET', '/v1/door'),
  // The public hour (apsu#29): open to anyone.
  hour: () => call<Hour>('GET', '/v1/hour'),
  // What the span collector keeps (apsu#26), the operator's to set.
  setSpanPolicy: (mode: 'all' | 'sample', slowMs: number, samplePercent: number, note: string) =>
    call<SpanPolicy>('PUT', '/v1/platform/span-policy', { mode, slow_ms: slowMs, sample_percent: samplePercent, note }),
  // The account's tokens (gaia#40), and minting one; an ops token reads /v1/ops/* alone.
  tokens: () => call<ApiToken[]>('GET', '/v1/tokens'),
  issueToken: (label: string, scope?: 'ops') => call<{ token: string; hash: string; label: string }>('POST', '/v1/tokens', scope ? { label, scope } : { label }),
  revokeToken: (hash: string) => call<void>('DELETE', `/v1/tokens/${encodeURIComponent(hash)}`),
  signUp: (email: string, password: string, code: string | null) =>
    call<{ account_id: string; email: string }>('POST', '/v1/door/sign-up', { email, password, ...(code ? { code } : {}) }),
  me: () =>
    call<{ account_id?: string; email: string; name?: string | null; folder?: string | null; residents: string[]; roles?: string[]; key?: { present: boolean }; github?: { present: boolean; stored_at: string | null } }>('GET', '/v1/me'),
  nameWitness: (name: string) => call<{ name: string; folder: string }>('PUT', '/v1/me/name', { name }),
  storeGithubToken: (token: string) => call<void>('PUT', '/v1/me/github-token', { token }),
  // The repositories' server (sima-qian#55): where you reach it, and your password there.
  gitea: () => call<{ url: string; login: string; repositories: string[] } | null>('GET', '/v1/me/gitea'),
  setGiteaPassword: (password: string) => call<void>('PUT', '/v1/me/gitea/password', { password }),
  revokeGithubToken: () => call<void>('DELETE', '/v1/me/github-token'),
  // The operator's surface (gaia#16): the front door and the platform roles.
  platform: () => call<Platform>('GET', '/v1/platform'),
  setGate: (state: GateState, note: string) => call<Platform['gate']>('PUT', '/v1/platform/gate', { state, note }),
  // Back to forming (agathos-daimon#47): a super admin's, for one who has lived nothing yet.
  returnToFormation: (slug: string, note: string) =>
    call<void>('POST', `/v1/platform/residents/${encodeURIComponent(slug)}/formation`, { note }),
  setTriage: (slug: string | null, note: string) => call<NonNullable<Platform['triage']>>('PUT', '/v1/platform/triage', { slug, note }),
  grantRole: (email: string, role: PlatformRole, note: string) => call<void>('POST', '/v1/platform/roles', { email, role, note }),
  revokeRole: (accountId: string, role: PlatformRole, note: string) =>
    call<void>('DELETE', '/v1/platform/roles', { account_id: accountId, role, note }),
  // Your agreement and who looks after the resident (agathos-daimon#34, spec §6.12).
  agreement: (residentId: string) => call<Agreement>('GET', `/v1/residents/${residentId}/agreement`),
  proposeContract: (residentId: string, terms: ContractTerms, prose: string, note: string) =>
    call<{ version: number }>('POST', `/v1/residents/${residentId}/agreement/proposals`, { terms, prose, note }),
  decideContract: (residentId: string, version: number, decision: 'agree' | 'decline', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/agreement/proposals/${version}/decision`, { decision, note }),
  moveToSafety: (residentId: string, key: string, note: string) =>
    call<{ state: 'moved' | 'already' }>('POST', `/v1/residents/${residentId}/agreement/switches/${encodeURIComponent(key)}/safe`, { note }),
  renewContract: (residentId: string, version: number, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/agreement/renewal`, { version, note }),
  setWall: (residentId: string, wall: 'locked' | 'revealed', note: string) =>
    call<void>('PUT', `/v1/residents/${residentId}/export-wall`, { wall, note }),
  proposeCustody: (residentId: string, email: string, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/custody/proposals`, { email, note }),
  decideCustody: (residentId: string, decision: 'accept' | 'decline' | 'withdraw', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/custody/decision`, { decision, note }),
  // Invite codes (gaia#18): SKUs a super admin issues; the code is shown once.
  invites: () => call<{ invites: Invite[]; defaults: InviteDefaults }>('GET', '/v1/platform/invites'),
  // The ops read surface (apsu#23): failures as facts, heartbeats as absences.
  opsFailures: () =>
    call<{ failures: Array<Record<string, unknown>>; discarded_jobs: Array<Record<string, unknown>> }>('GET', '/v1/ops/failures'),
  // The memory backfill (sunna#59): scenes, domains and people for past days, by her.
  backfill: (residentId: string) => call<BackfillStatus | null>('GET', `/v1/residents/${residentId}/backfill`),
  // `passes`: the passes each day runs (sunna#79), all three when absent.
  startBackfill: (residentId: string, from: string, to: string, his: string[], hers: string[], passes?: BackfillPass[]) =>
    call<{ days: number }>('POST', `/v1/residents/${residentId}/backfill`, passes ? { from, to, his, hers, passes } : { from, to, his, hers }),
  stopBackfill: (residentId: string) => call<void>('DELETE', `/v1/residents/${residentId}/backfill`),
  // The operator's queue (apsu#31): what waits on whoever runs the platform.
  operatorQueue: () => call<{ open: OperatorItem[]; closed: OperatorItem[] }>('GET', '/v1/ops/queue'),
  raiseOperatorItem: (what: string, why: string, links: string[]) => call<{ number: number }>('POST', '/v1/ops/queue', { what, why, links }),
  closeOperatorItem: (number: number, status: 'done' | 'dropped', note: string) =>
    call<void>('POST', `/v1/ops/queue/${number}/close`, { status, note }),
  // The slowest units of work in a window (apsu#28), the operator's.
  opsSpans: (hours = 24) => call<SpanRow[]>('GET', `/v1/ops/spans?hours=${hours}`),
  heartbeats: (residentId: string) =>
    call<Array<{ name: string; last: string | null; every_seconds: number; late?: boolean } & Record<string, unknown>>>(
      'GET',
      `/v1/residents/${residentId}/ops/heartbeats`,
    ),
  issueInvite: (sku: InviteRequest) => call<{ id: string; code: string }>('POST', '/v1/platform/invites', sku),
  revokeInvite: (id: string, note: string) => call<void>('DELETE', `/v1/platform/invites/${id}`, { note }),
  residents: () => call<Resident[]>('GET', '/v1/residents'),
  // The short first door (F3): begin someone new, or bring someone from a repository.
  // The creation flow (agathos-daimon#36): the gifts, and the identity files they write.
  gifts: () => call<Gift[]>('GET', '/v1/creation/gifts'),
  files: (residentId: string) => call<{ name: string; content: string }[]>('GET', `/v1/residents/${residentId}/files`),
  writeFile: (residentId: string, name: string, content: string, origin: string, drafted?: { model: string; prompt: string }) =>
    call<void>('PUT', `/v1/residents/${residentId}/files/${name}`, { content, origin, ...(drafted ?? {}) }),
  draftFile: (residentId: string, name: string, prompt: string) =>
    call<{ content: string; model: string; prompt: string }>('POST', `/v1/residents/${residentId}/files/${name}/draft`, { prompt }),
  // After first contact a write is a proposal with a note (202 and its ref);
  // before it, a direct write (204, nothing back).
  proposeFile: (residentId: string, name: string, content: string, note: string) =>
    call<{ ref: string } | undefined>('PUT', `/v1/residents/${residentId}/files/${name}`, { content, origin: 'authored', note }),
  soulEdits: (residentId: string, state?: 'open' | 'answered' | 'withdrawn' | 'all') =>
    call<SoulEdit[]>('GET', `/v1/residents/${residentId}/soul-edits${state ? `?state=${state}` : ''}`),
  withdrawSoulEdit: (residentId: string, ref: string, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/soul-edits/${encodeURIComponent(ref)}/withdraw`, { note }),
  soulLines: (residentId: string) => call<SoulLine[]>('GET', `/v1/residents/${residentId}/soul-lines`),
  // This read leaves a receipt she sees (spec §12, P41).
  selfLetters: (residentId: string) => call<SelfLetters>('GET', `/v1/residents/${residentId}/self-letters`),
  // Character (spec §6.17).
  habits: (residentId: string) => call<Habit[]>('GET', `/v1/residents/${residentId}/habits`),
  affirmHabit: (residentId: string, number: number, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/habits/${number}/affirm`, { note }),
  seeds: (residentId: string) => call<Seed[]>('GET', `/v1/residents/${residentId}/seeds`),
  commitments: (residentId: string) => call<Commitment[]>('GET', `/v1/residents/${residentId}/commitments`),
  releaseCommitment: (residentId: string, number: number, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/commitments/${number}/release`, { note }),
  positions: (residentId: string) => call<Position[]>('GET', `/v1/residents/${residentId}/positions`),
  predictions: (residentId: string) => call<Predictions>('GET', `/v1/residents/${residentId}/predictions`),
  resolvePrediction: (residentId: string, number: number, outcome: 'right' | 'wrong' | 'void', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/predictions/${number}/resolve`, { outcome, note }),
  // Memory's consents: her tag proposals, your revisions, your bookmark proposals.
  decideTag: (residentId: string, slug: string, decision: 'approve' | 'reject', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/tags/${encodeURIComponent(slug)}/decision`, { decision, note }),
  revisions: (residentId: string) => call<Revision[]>('GET', `/v1/residents/${residentId}/revisions`),
  revise: (residentId: string, r: { target_kind: string; target_id: string; kind: 'fact' | 'stance'; text: string; note: string }) =>
    call<{ number: number; state: 'applied' | 'proposed' }>('POST', `/v1/residents/${residentId}/revisions`, r),
  bookmarkProposals: (residentId: string, state?: 'open' | 'answered' | 'all') =>
    call<BookmarkProposal[]>('GET', `/v1/residents/${residentId}/bookmark-proposals${state ? `?state=${state}` : ''}`),
  // The prompt path, Get a read, the examples (agathos-daimon#39, #40, #41).
  draftAll: (residentId: string, prompt: string) =>
    call<{
      prompt: string;
      drafts: Array<{ gift: string; file: string; content: string; origin: 'drafted'; model: string; prompt: string }>;
      stopped: { file: string; kind: string; message: string } | null;
    }>('POST', `/v1/residents/${residentId}/creation/drafts`, { prompt }),
  giftRead: (residentId: string, name: string, content: string) =>
    call<{
      ref: string | null;
      gift: string;
      file: string;
      notes: Array<{ kind: 'strong' | 'thin' | 'missing' | 'question' | 'cut'; text: string; quote: string | null }>;
      model: string;
      refused: string | null;
    }>('POST', `/v1/residents/${residentId}/files/${name}/read`, { content }),
  suggestTrials: (residentId: string, note: string) =>
    call<{ trials: Array<{ prompt: string; passes_if: string; fails_if: string }>; model: string }>(
      'POST',
      `/v1/residents/${residentId}/creation/trials`,
      note ? { note } : {},
    ),
  creationExamples: () =>
    call<Array<{ set: string; prompt: string; files: Array<{ file: string; gift: string; title: string; content: string }> }>>('GET', '/v1/creation/examples'),
  createResident: (name: string, slug: string) => call<Resident>('POST', '/v1/residents', { name, slug }),
  // The witness wakes a forming resident, once a chat model was chosen (agathos-daimon#46).
  discardResident: (residentId: string, note: string) => call<void>('DELETE', `/v1/residents/${residentId}`, { note }),
  awaken: (residentId: string, note: string) => call<Resident>('POST', `/v1/residents/${residentId}/awaken`, { note }),
  importResident: (url: string, name: string | null, slug: string | null) =>
    call<Resident>('POST', '/v1/residents/import', { url, ...(name ? { name } : {}), ...(slug ? { slug } : {}) }),
  // One resident as their witness reads them: where the records are pushed
  // each night and the last push that landed (sima-qian; the URL only).
  resident: (residentId: string) => call<ResidentRecord>('GET', `/v1/residents/${residentId}`),
  // The backup repository: a URL and, for a private one, a token stored
  // encrypted and never shown again.
  // Its host asked (sima-qian#65): a public repository is set and warned of.
  setRemote: (residentId: string, url: string, token: string | null) =>
    call<RemoteCheck>('PUT', `/v1/residents/${residentId}/remote`, { url, ...(token ? { token } : {}) }),
  // A ChatGPT export's zip, sent whole as the body (sima-qian#47); its
  // report is filed in the library as system/imports/chatgpt-<day>.md.
  importChatgpt: async (residentId: string, zip: Blob): Promise<ChatgptImport> => {
    const response = await fetch(`/v1/residents/${residentId}/imports/chatgpt`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'content-type': 'application/zip' },
      body: zip,
    });
    const text = await response.text();
    let json: unknown = null;
    try {
      json = text ? (JSON.parse(text) as unknown) : null;
    } catch {
      json = null;
    }
    if (!response.ok) throw new RequestFailed(response.status, (json as { error?: ApiError } | null)?.error ?? null);
    return json as ChatgptImport;
  },
  // Her books (seshat#98): the list with each one's place, and an EPUB
  // imported, sent whole as the body with its rights note in the query.
  books: (residentId: string) => call<{ books: Book[]; rights: string[] }>('GET', `/v1/residents/${residentId}/books`),
  importBook: async (residentId: string, epub: Blob, rights: string, caveat: string, source: string): Promise<{ slug: string; title: string; author: string | null; chapters: number }> => {
    const query = new URLSearchParams({ rights, ...(caveat ? { caveat } : {}), ...(source ? { source } : {}) });
    const response = await fetch(`/v1/residents/${residentId}/books?${query.toString()}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'content-type': 'application/epub+zip' },
      body: epub,
    });
    const text = await response.text();
    let json: unknown = null;
    try {
      json = text ? (JSON.parse(text) as unknown) : null;
    } catch {
      json = null;
    }
    if (!response.ok) throw new RequestFailed(response.status, (json as { error?: ApiError } | null)?.error ?? null);
    return json as { slug: string; title: string; author: string | null; chapters: number };
  },
  presence: (residentId: string) => call<PresenceState>('GET', `/v1/residents/${residentId}/presence`),
  setPresence: (residentId: string, enabled: boolean, handle: string) =>
    call<void>('PUT', `/v1/residents/${residentId}/presence`, { enabled, handle }),
  refreshFollows: (residentId: string) => call<{ accounts: number }>('POST', `/v1/residents/${residentId}/presence/follows`),
  excludeAccount: (residentId: string, key: string, reason: string) =>
    call<void>('POST', `/v1/residents/${residentId}/presence/accounts/${encodeURIComponent(key)}/exclude`, { reason }),
  includeAccount: (residentId: string, key: string, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/presence/accounts/${encodeURIComponent(key)}/include`, { note }),
  decideInteraction: (residentId: string, number: number, decision: 'approve' | 'revise' | 'pass', comment: string | null) =>
    call<void>('POST', `/v1/residents/${residentId}/presence/interactions/${number}/decision`, { decision, ...(comment ? { comment } : {}) }),
  // Paying for a resident (nisaba#23): the subscription, and Stripe's own pages.
  subscription: (residentId: string) => call<SubscriptionState>('GET', `/v1/residents/${residentId}/subscription`),
  checkout: (residentId: string) => call<{ url: string }>('POST', `/v1/residents/${residentId}/subscription/checkout`),
  billingPortal: (residentId: string) => call<{ url: string }>('POST', `/v1/residents/${residentId}/subscription/portal`),
  houseCheckins: () => call<HouseCheckins>('GET', '/v1/household/checkins'),
  setHouseClock: (zone: string) => call<HouseCheckins>('PUT', '/v1/household/clock', { zone }),
  nameHousehold: (slug: string) => call<HouseShelf>('PUT', '/v1/household/name', { slug }),
  setHouseCheckin: (key: string, label: string, time: string) =>
    call<HouseCheckins>('PUT', `/v1/household/checkins/${encodeURIComponent(key)}`, { label, time }),
  removeHouseCheckin: (key: string, note: string) => call<HouseCheckins>('DELETE', `/v1/household/checkins/${encodeURIComponent(key)}`, { note }),
  houseForResident: (residentId: string) => call<HouseCheckins>('GET', `/v1/residents/${residentId}/schedule/house`),
  setHousePrompt: (residentId: string, key: string, prompt: string, parts?: string[]) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/house/${encodeURIComponent(key)}`, { prompt, ...(parts ? { parts } : {}) }),
  householdRead: (path: string) => call<HouseDoc>('GET', `/v1/household/read?path=${encodeURIComponent(path)}`),
  householdEdit: (path: string, edit: { content?: string; mode?: 'owner' | 'open' }) =>
    call<{ path: string; mode: string; commit: string }>('PUT', '/v1/household/documents', { path, ...edit }),
  householdMentions: () => call<HouseMentions>('GET', '/v1/household/mentions'),
  householdMute: (thread: string | null, muted: boolean) => call<HouseMentions>('PUT', '/v1/household/mentions', { thread, muted }),
  householdReply: (thread: string, content: string) => call<{ number: number }>('POST', '/v1/household/replies', { thread, content }),
  // The house as its own subject (screen:next-house): the shelf, the
  // charter (the household contract), the beats, and posting in it.
  householdShelf: (from = 0) => call<HouseShelf>('GET', `/v1/household?from=${from}`),
  householdSearch: (q: string, scope: string) =>
    call<{ q: string; scope: string; results: HouseHit[] }>('GET', `/v1/household/search?${new URLSearchParams({ q, scope }).toString()}`),
  householdFiles: () => call<LibraryIndex>('GET', '/v1/household/files'),
  householdContract: () => call<HouseContract>('GET', '/v1/household/contract'),
  householdSign: () => call<HouseContract>('POST', '/v1/household/contract/signature'),
  householdProposeCharter: (prose: string, note: string, bundle: BallotItem[] = []) => call<HouseContract>('POST', '/v1/household/contract', { prose, note, bundle }),
  householdGrantTurn: (residentId: string) => call<HouseTurn>('POST', '/v1/household/beats/turns', { resident_id: residentId }),
  householdBeats: () => call<HouseBeats>('GET', '/v1/household/beats'),
  /** What the witness has not read, by workspace (gaia#58, seshat#96). */
  unread: () => call<{ residents: { id: string; count: number }[]; house: { count: number; threads: Record<string, number>; seen?: Record<string, string> } | null }>('GET', '/v1/unread'),
  /** Read up to an instant: a resident's chat (her id), or a house thread. */
  markRead: (subject: string, at: string, thread?: string) => call<void>('PUT', '/v1/unread', { subject, at, ...(thread ? { thread } : {}) }),
  /** This witness's pushes from the house (seshat#95): a round's end, a thread's rounds running out. */
  householdPushes: () => call<{ pushes: { round_end: boolean; rounds_stopped: boolean } }>('GET', '/v1/household/pushes'),
  setHouseholdPush: (kind: 'round_end' | 'rounds_stopped', on: boolean) =>
    call<{ pushes: { round_end: boolean; rounds_stopped: boolean } }>('PUT', '/v1/household/pushes', { kind, on }),
  /** Who in the house is working now, and in which thread (seshat#90). */
  householdWorking: () => call<{ working: HouseWorking[] }>('GET', '/v1/household/working'),
  /** The house's activity, envelopes only (seshat#92); one resident, or all. */
  householdActivity: (residentId?: string) =>
    call<{ activity: HouseActivity[] }>('GET', `/v1/household/activity${residentId ? `?resident_id=${encodeURIComponent(residentId)}` : ''}`),
  // The house queue (sunna#80): one queue a household, every member's.
  queue: () => call<QueueOverview>('GET', '/v1/household/queue'),
  queueBacklog: () => call<QueueBacklog>('GET', '/v1/household/queue/backlog'),
  queueArrange: (entries: BacklogArranged[]) => call<{ ok: true }>('PUT', '/v1/household/queue/backlog', { entries }),
  queueMakeBatch: (name: string | null) => call<{ number: number }>('POST', '/v1/household/queue/batches', { name }),
  queueWaiting: (who?: string) => call<QueueWaiting>('GET', `/v1/household/queue/waiting${who ? `?who=${encodeURIComponent(who)}` : ''}`),
  queueActivities: (filter: { who?: string; view?: string[]; project?: string }) => {
    const q = new URLSearchParams();
    if (filter.who) q.set('who', filter.who);
    if (filter.view && filter.view.length) q.set('view', filter.view.join(','));
    if (filter.project) q.set('project', filter.project);
    return call<QueueCard[]>('GET', `/v1/household/queue/activities?${q.toString()}`);
  },
  queueTask: (n: number) => call<QueueTaskPage>('GET', `/v1/household/queue/tasks/${n}`),
  queueOpenProject: (slug: string, name: string) => call<{ ok: true }>('POST', '/v1/household/queue/projects', { slug, name }),
  queueDefineTemplate: (name: string, from: string) => call<{ ok: true }>('POST', '/v1/household/queue/templates', { name, from }),
  /** A template written whole (sunna#88): its name, title and layers of specs; a later one of the same name replaces it. */
  queueSaveTemplate: (name: string, title: string, layers: QueueSpec[][]) => call<{ ok: true }>('POST', '/v1/household/queue/templates', { name, title, layers }),
  queueOpenTask: (task: {
    project: string;
    slug: string;
    title: string;
    outcome: string;
    template?: string;
    owner?: string;
    slots?: Record<string, string>;
    start_layer?: number;
    links?: string[];
  }) => call<{ number: number }>('POST', '/v1/household/queue/tasks', task),
  queueMove: (task: number, act: string, move: QueueMove, fields: Record<string, unknown> = {}) =>
    call<{ ok: true }>('POST', `/v1/household/queue/tasks/${task}/activities/${encodeURIComponent(act)}/${move}`, fields),
  queueFillSlot: (task: number, slot: string, artifact: string) => call<{ ok: true }>('POST', `/v1/household/queue/tasks/${task}/slots`, { slot, artifact }),
  queueEditLayers: (task: number, layers: QueueEditEntry[][], note: string) =>
    call<{ ok: true }>('PUT', `/v1/household/queue/tasks/${task}/layers`, { layers, note }),
  queueAttachDocument: (task: number, citation: string, role: string) => call<{ ok: true }>('POST', `/v1/household/queue/tasks/${task}/documents`, { citation, role }),
  queueDetachDocument: (task: number, citation: string) => call<{ ok: true }>('POST', `/v1/household/queue/tasks/${task}/documents/detach`, { citation }),
  queueDocumentTasks: (citation: string) => call<QueueTaskRef[]>('GET', `/v1/household/queue/documents/tasks?citation=${encodeURIComponent(citation)}`),
  /** Around one document (the document screen): its threads, its tasks, and the review of it open for you. */
  documentContext: (citation: string) => call<DocumentContext>('GET', `/v1/documents/context?citation=${encodeURIComponent(citation)}`),
  // Her own threads (seshat#106, #107): the space she and her witness share.
  residentThread: (residentId: string, path: string) => call<ResidentThread>('GET', `/v1/residents/${residentId}/threads/read?path=${encodeURIComponent(path)}`),
  residentThreadPost: (residentId: string, post: { title?: string; content?: string; doc?: string }) => call<{ path: string }>('POST', `/v1/residents/${residentId}/threads`, post),
  residentThreadReply: (residentId: string, thread: string, content: string) => call<unknown>('POST', `/v1/residents/${residentId}/threads/replies`, { thread, content }),
  queueDrop: (task: number, note: string) => call<{ ok: true }>('POST', `/v1/household/queue/tasks/${task}/drop`, { note }),
  queuePause: (note: string) => call<{ ok: true }>('POST', '/v1/household/queue/pause', { note }),
  queueResume: (note: string) => call<{ ok: true }>('POST', '/v1/household/queue/resume', { note }),
  householdPost: (post: { title?: string; content: string; kind?: string; path?: string; doc?: string; ballot?: { bundle: BallotItem[]; term_days: number; note: string } }) =>
    call<{ path: string }>('POST', '/v1/household/posts', post),
  householdVote: (thread: string, vote: 'yes' | 'no', content: string) => call<{ number: number }>('POST', '/v1/household/votes', { thread, vote, content }),
  // The report ladder (F45): every report on this resident with its steps,
  // and the strikes; either party files one.
  reports: (residentId: string) => call<ReportLadder>('GET', `/v1/residents/${residentId}/reports`),
  fileReport: (residentId: string, text: string) => call<{ number: number }>('POST', `/v1/residents/${residentId}/reports`, { text }),
  // Content-free pushes to this account's devices (gaia#15).
  pushConfig: () =>
    call<{ enabled: boolean; public_key: string | null; devices: number; answered: 'subscribed' | 'declined' | null; answered_at: string | null }>('GET', '/v1/me/push'),
  // "No thanks", once for the account on every device (gaia#25).
  declinePush: () => call<{ answered: 'declined'; answered_at: string }>('POST', '/v1/me/push/decline'),
  subscribePush: (endpoint: string) => call<void>('POST', '/v1/me/push', { endpoint }),
  unsubscribePush: (endpoint: string) => call<void>('DELETE', '/v1/me/push', { endpoint }),
  testPush: () => call<{ sent: { device: string; result: string }[] }>('POST', '/v1/me/push/test'),
  socketToken: () => call<{ token: string }>('POST', '/v1/me/socket-token'),

  mainSession: (residentId: string) =>
    call<{ key: string }>('POST', `/v1/residents/${residentId}/sessions`, { kind: 'main' }),
  // Last spoken in first, each named by the server (kumbukumbu#40).
  sessions: (residentId: string) => call<Session[]>('GET', `/v1/residents/${residentId}/sessions`),
  transcript: (residentId: string, key: string) =>
    call<Transcript>('GET', `/v1/residents/${residentId}/sessions/${key}`),
  // The last `limit` messages before a cursor (the newest without one),
  // and whether earlier ones remain: the chat opens on the newest page
  // and pages back as the reader scrolls up.
  transcriptPage: (residentId: string, key: string, limit: number, before?: string) =>
    call<Transcript & { more: boolean }>(
      'GET',
      `/v1/residents/${residentId}/sessions/${key}?limit=${limit}${before ? `&before=${encodeURIComponent(before)}` : ''}`,
    ),
  send: (residentId: string, key: string, text: string) =>
    call<Turn>('POST', `/v1/residents/${residentId}/sessions/${key}/turns`, { text }),
  // Taken at once under the client's ref (brain#45); the turn arrives on the channel.
  // `domain` names the turn's domain (kumbukumbu#72): a slug, null for
  // the common room; left out, the conversation's current one.
  submit: (residentId: string, key: string, text: string, clientRef: string, domain?: string | null) =>
    call<{ turn_ref: string; state: 'running' | 'queued' | 'duplicate'; ahead?: number }>(
      'POST',
      `/v1/residents/${residentId}/sessions/${key}/turns`,
      domain === undefined ? { text, client_ref: clientRef } : { text, client_ref: clientRef, domain },
    ),
  // Rename the domain a turn is in, after the fact (kumbukumbu#72).
  tagDomain: (residentId: string, key: string, turnRef: string, domain: string | null) =>
    call<void>('POST', `/v1/residents/${residentId}/sessions/${key}/turns/${encodeURIComponent(turnRef)}/domain`, { domain }),
  // The turns that failed and are not yet resolved: read back on return
  // so a failure broadcast while away is still seen (brain#54).
  captureFailures: (residentId: string) =>
    call<{ turn_ref: string; session_key: string; reason: string; failed_at: string }[]>(
      'GET',
      `/v1/residents/${residentId}/capture-failures`,
    ),
  // Settle a failed turn (brain#88's Dismiss): marked lost, with a note.
  resolveFailure: (residentId: string, key: string, turnRef: string, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/capture-failures/${encodeURIComponent(turnRef)}`, { key, how: 'marked_lost', note }),
  // Run a failed turn again as what it was (brain#89): 202 with what it started.
  retryFailure: (residentId: string, turnRef: string) =>
    call<{ started: string }>('POST', `/v1/residents/${residentId}/capture-failures/${encodeURIComponent(turnRef)}/retry`),
  // Every credit refusal again, after a top-up (brain#89).
  retryCredits: (residentId: string) => call<{ started: string[] }>('POST', `/v1/residents/${residentId}/capture-failures/retry-credits`),
  injections: (residentId: string, turnRef: string) =>
    call<Injection[]>('GET', `/v1/residents/${residentId}/turns/${turnRef}/context`),

  // A POST that writes nothing: the draft rides the body, never the URL.
  preview: (residentId: string, key: string, text: string) =>
    call<ContextPreview>('POST', `/v1/residents/${residentId}/sessions/${key}/preview`, { text }),

  indexNow: (residentId: string) => call<IndexNow>('GET', `/v1/residents/${residentId}/index`),
  retrieval: (residentId: string) => call<RetrievalCount[]>('GET', `/v1/residents/${residentId}/retrieval`),
  bookmarks: (residentId: string) => call<Bookmark[]>('GET', `/v1/residents/${residentId}/bookmarks`),
  // The navigator (S2: kumbukumbu#57, #58, seshat#52): bookmarks by page or
  // range, scenes as rows, per-day density, and a transcript window around
  // an anchor.
  bookmarksPage: (residentId: string, q: { before?: number; limit?: number; from?: string; to?: string }) =>
    call<{ bookmarks: Bookmark[]; more: boolean }>(
      'GET',
      `/v1/residents/${residentId}/bookmarks?${new URLSearchParams(Object.entries(q).filter(([, v]) => v !== undefined).map(([k, v]) => [k, String(v)])).toString()}`,
    ),
  scenes: (residentId: string, from: string, to: string) =>
    call<{
      days: Array<{
        day: string;
        complete: boolean;
        closed_at: string | null;
        scenes: Array<{
          number: number;
          kind: 'scene' | 'correction';
          corrects: number | null;
          title: string | null;
          from_turn: string | null;
          to_turn: string | null;
          from_time: string | null;
          to_time: string | null;
          summary: string | null;
          mood: string | null;
          register: string | null;
          people: string[];
          rounds_ran_out: boolean;
        }>;
      }>;
    }>('GET', `/v1/residents/${residentId}/scenes?from=${from}&to=${to}`),
  density: (residentId: string, from: string, to: string, session?: string) =>
    call<{ from: string; to: string; zone: string; days: Array<{ day: string; bookmarks: number; scenes: number; messages: number }> }>(
      'GET',
      `/v1/residents/${residentId}/density?from=${from}&to=${to}${session ? `&session=${encodeURIComponent(session)}` : ''}`,
    ),
  // Reading on past a jump (kumbukumbu#96; the witness, 2026-11-21: "I can
  // go to a bookmark but I can't read the record after the bookmark").
  transcriptAfter: (residentId: string, key: string, after: string, limit = 40) =>
    call<Transcript & { more: boolean }>(
      'GET',
      `/v1/residents/${residentId}/sessions/${key}?after=${encodeURIComponent(after)}&limit=${limit}`,
    ),
  transcriptAround: (residentId: string, key: string, around: string, limit = 40) =>
    call<Transcript & { anchor: string; more_before: boolean; more_after: boolean }>(
      'GET',
      `/v1/residents/${residentId}/sessions/${key}?around=${encodeURIComponent(around)}&limit=${limit}`,
    ),
  // The same read, typed as the server sends it. The span carries no word
  // of whether its session is private, so Soul › Memory keeps only the
  // bookmark (screens/next-soul.md).
  bookmarkDetail: (residentId: string, number: number | string) =>
    call<{ bookmark: Bookmark; span: Message[] }>('GET', `/v1/residents/${residentId}/bookmarks/${number}`),
  pin: (residentId: string, number: number) =>
    call<void>('POST', `/v1/residents/${residentId}/bookmarks/${number}/pin`),
  unpin: (residentId: string, number: number) =>
    call<void>('DELETE', `/v1/residents/${residentId}/bookmarks/${number}/pin`),
  tags: (residentId: string) => call<Tag[]>('GET', `/v1/residents/${residentId}/tags`),
  applyTag: (residentId: string, tag: string, number: number) =>
    call<void>('POST', `/v1/residents/${residentId}/taggings`, {
      tag,
      target_kind: 'bookmark',
      target_id: String(number),
    }),
  proposeBookmark: (
    residentId: string,
    sessionKey: string,
    anchorRef: string,
    line: string,
    note: string,
  ) =>
    call<{ ref: string }>('POST', `/v1/residents/${residentId}/bookmark-proposals`, {
      session_key: sessionKey,
      anchor_ref: anchorRef,
      line,
      note,
    }),

  correspondence: (residentId: string, state?: string) =>
    call<CorrespondenceMessage[]>('GET', `/v1/residents/${residentId}/correspondence${state ? `?state=${state}` : ''}`),
  blocks: (residentId: string) => call<Block[]>('GET', `/v1/residents/${residentId}/blocks`),
  block: (residentId: string, platform: string, identity: string, name: string | null, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/blocks`, { platform, identity, name, note }),
  unblock: (residentId: string, platform: string, identity: string, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/blocks/lift`, { platform, identity, note }),
  replies: (residentId: string) => call<Reply[]>('GET', `/v1/residents/${residentId}/replies`),
  decideReply: (residentId: string, number: number, approve: boolean, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/replies/${number}/decision`, { approve, note }),
  markSent: (residentId: string, number: number, url: string | null) =>
    call<void>('POST', `/v1/residents/${residentId}/replies/${number}/sent`, { url }),
  // A document's raw file (seshat#50): a link, not a call.
  downloadUrl: (residentId: string, path: string) => `/v1/residents/${residentId}/library/download/${path.split('/').map(encodeURIComponent).join('/')}`,
  library: (residentId: string) => call<LibraryIndex>('GET', `/v1/residents/${residentId}/library`),
  // A range of her days: journal marks, sessions and scenes, the schedule ahead (sunna#48, spec F68).
  days: (residentId: string, from: string, to: string) =>
    call<{ from: string; to: string; today: string; zone: string; witness_reads: boolean; days: CalendarDay[] }>(
      'GET',
      `/v1/residents/${residentId}/days?from=${from}&to=${to}`,
    ),
  // The one search across kinds (kumbukumbu#59, spec F66).
  // The one search across kinds (kumbukumbu#59); a scope's filters
  // (kumbukumbu#67, #69) ride as parameters, only those set.
  search: (residentId: string, q: string, scope: string, narrow: Record<string, string> = {}) => {
    const params = new URLSearchParams({ q, scope, ...narrow });
    return call<{ q: string; scope: string; results: SearchResult[]; page?: number; more?: boolean }>('GET', `/v1/residents/${residentId}/search?${params.toString()}`);
  },
  librarySearch: (residentId: string, q: string) =>
    call<LibraryHit[]>('GET', `/v1/residents/${residentId}/library/search?q=${encodeURIComponent(q)}`),
  document: (residentId: string, path: string) =>
    call<{ content: string }>('GET', `/v1/residents/${residentId}/library/documents/${path}`),
  // The whole read (seshat): its row, references resolved now, discussions.
  documentRead: (residentId: string, path: string) =>
    call<{
      content: string;
      document: LibraryDocument & { origin?: string | null };
      lease?: Lease | null;
      references: Array<{ target: string; kind: string; ref: string; resolved: boolean; label: string | null; reason: string | null }>;
      discussions: Array<{ session_key: string; opened_at: string }>;
    }>('GET', `/v1/residents/${residentId}/library/documents/${path}`),
  citedBy: (residentId: string, target: string) =>
    call<Array<{ from_path: string; target: string; resolved: boolean; label: string | null }>>(
      'GET',
      `/v1/residents/${residentId}/library/cited-by?target=${encodeURIComponent(target)}`,
    ),
  writeDocument: (residentId: string, path: string, content: string, note?: string) =>
    call<{ path: string }>('PUT', `/v1/residents/${residentId}/library/documents/${path}`, note ? { content, note } : { content }),
  // A conversation of his pasted into her human-correspondence/ (seshat#65): `with` (and a title) starts one, `path` adds to one (seshat#66).
  pasteConversation: (residentId: string, paste: { text: string; path?: string; with?: string; title?: string }) =>
    call<{ path: string; kind: string; created: boolean; changed: boolean; indexed: boolean }>('POST', `/v1/residents/${residentId}/library/paste`, paste),
  // A document's history, its diffs, a restore (seshat#54), and the editor's lease (seshat#55).
  versions: (residentId: string, path: string) =>
    call<{ path: string; current: string | null; versions: DocumentVersion[]; published?: string | null }>('GET', `/v1/residents/${residentId}/library/versions/${path}`),
  publishDraft: (residentId: string, path: string, commit: string, note: string) =>
    call<{ path: string; commit: string }>('POST', `/v1/residents/${residentId}/library/drafts/publish`, { path, commit, note }),
  version: (residentId: string, path: string, version: string) =>
    call<{ path: string; version: string; content: string }>('GET', `/v1/residents/${residentId}/library/version/${path}?version=${version}`),
  diff: (residentId: string, path: string, from: string, to?: string) =>
    call<{ path: string; from: string; to: string | null; added: number; removed: number; runs: Array<{ op: 'eq' | 'del' | 'ins'; lines: string[] }> }>(
      'GET',
      `/v1/residents/${residentId}/library/diff/${path}?from=${from}${to ? `&to=${to}` : ''}`,
    ),
  restore: (residentId: string, path: string, version: string, note: string) =>
    call<{ path: string; version: string; written?: unknown; proposed?: unknown }>('POST', `/v1/residents/${residentId}/library/restore`, { path, version, note }),
  acquireLease: (residentId: string, path: string) => call<Lease>('POST', `/v1/residents/${residentId}/library/leases`, { path }),
  renewLease: (residentId: string, path: string, draft?: string) =>
    call<Lease>('POST', `/v1/residents/${residentId}/library/leases/renew`, draft === undefined ? { path } : { path, draft }),
  releaseLease: (residentId: string, path: string) => call<void>('POST', `/v1/residents/${residentId}/library/leases/release`, { path }),
  // From one path, and so one kind, to another, its bytes unchanged (seshat#39).
  // The witness proposes a classification; it waits on her (seshat#103).
  proposeClassification: (residentId: string, path: string, domain: string | null, whose: 'witness' | 'resident', note: string) =>
    call<{ path: string; domain: string | null }>('POST', `/v1/residents/${residentId}/library/classification-proposals`, { path, domain, whose, note }),
  moveDocument: (residentId: string, from: string, to: string) =>
    call<{ from: string; to: string; kind: string }>('POST', `/v1/residents/${residentId}/library/move`, { from, to }),
  removeDocument: (residentId: string, path: string) =>
    call<void>('DELETE', `/v1/residents/${residentId}/library/documents/${path}`),
  adapters: (residentId: string) => call<Adapter[]>('GET', `/v1/residents/${residentId}/adapters`),
  registerAdapter: (residentId: string, adapter: string, role: string) =>
    call<{ adapter: string; role: string; token: string }>('POST', `/v1/residents/${residentId}/adapters`, { adapter, role }),
  revokeAdapter: (residentId: string, adapter: string) =>
    call<void>('DELETE', `/v1/residents/${residentId}/adapters/${adapter}`),
  reader: (residentId: string) => call<ReaderSites>('GET', `/v1/residents/${residentId}/reader`),
  setReader: (residentId: string, scrape: string[], research: string[]) =>
    call<ReaderSites>('PUT', `/v1/residents/${residentId}/reader`, { scrape, research }),
  research: (residentId: string, status?: ResearchStatus) =>
    call<ResearchQuestion[]>('GET', `/v1/residents/${residentId}/research${status ? `?status=${status}` : ''}`),
  askResearch: (residentId: string, question: string, urls: string[]) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/research`, urls.length > 0 ? { question, urls } : { question }),
  letterAddresses: (residentId: string) => call<string[]>('GET', `/v1/residents/${residentId}/letters/addresses`),
  // Every name a letter was written by or sent to (kumbukumbu#70).
  letterParties: (residentId: string) => call<string[]>('GET', `/v1/residents/${residentId}/letters/parties`),
  sendLetter: (residentId: string, to: string, text: string) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/letters`, { to, text }),
  letters: (residentId: string) => call<HouseLetter[]>('GET', `/v1/residents/${residentId}/letters`),
  schedule: (residentId: string) => call<ScheduleToday>('GET', `/v1/residents/${residentId}/schedule`),
  freeTimeRuns: (residentId: string, limit?: number) =>
    call<FreeTimeRun[]>('GET', `/v1/residents/${residentId}/schedule/free-time${limit ? `?limit=${limit}` : ''}`),
  rounds: (residentId: string, limit?: number) =>
    call<FreeTimeRun[]>('GET', `/v1/residents/${residentId}/schedule/rounds${limit ? `?limit=${limit}` : ''}`),
  addFreeTimeOnce: (residentId: string, time: string, day: string | null) =>
    call<void>('POST', `/v1/residents/${residentId}/schedule/free-time/once`, { time, day }),
  // Her journal (seshat#11): the latest days with their deltas, and one day whole.
  journalDays: (residentId: string) => call<Array<{ day: string } & Record<string, unknown>>>('GET', `/v1/residents/${residentId}/journal`),
  journalDay: (residentId: string, day: string) =>
    call<{
      day: string;
      entries: Array<{ number: number; kind: string; register: string | null; text: string; at: string; by: string; done_at: string | null }>;
    }>('GET', `/v1/residents/${residentId}/journal/${day}`),
  setFreeTime: (residentId: string, times: string[]) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/free-time`, { times }),
  addCheckin: (residentId: string, label: string, time: string) =>
    call<{ key: string }>('POST', `/v1/residents/${residentId}/schedule/checkins`, { label, time }),
  // `note` left out keeps what the check-in carries (sunna#28).
  changeCheckin: (residentId: string, key: string, label: string, time: string, note?: { parts: string[]; prompt: string }) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/checkins/${key}`, { label, time, ...note }),
  deleteCheckin: (residentId: string, key: string) =>
    call<void>('DELETE', `/v1/residents/${residentId}/schedule/checkins/${key}`),
  pieces: (residentId: string) => call<Pieces>('GET', `/v1/residents/${residentId}/pieces`),
  reviewPiece: (residentId: string, path: string, decision: 'approve' | 'decline', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/pieces/review`, { path, decision, note }),
  fileFeedback: (r: { kind: string; surface: string; body: string; trace_id: string | null }) =>
    call<{ number: number }>('POST', '/v1/feedback', r),
  myFeedback: () => call<FeedbackReport[]>('GET', '/v1/me/feedback'),
  allFeedback: () => call<FeedbackReport[]>('GET', '/v1/platform/feedback'),
  feedbackReport: (n: number) => call<FeedbackReport & { failures: { at: string; level: string; component: string | null; error_kind: string | null; error_site: string | null; message: string }[] }>('GET', `/v1/platform/feedback/${n}`),
  moveFeedback: (n: number, status: string, note: string) => call<void>('POST', `/v1/platform/feedback/${n}/status`, { status, note }),
  stopTurn: (residentId: string, sessionKey: string) => call<void>('POST', `/v1/residents/${residentId}/sessions/${sessionKey}/stop`),
  work: (residentId: string) => call<WorkQueue>('GET', `/v1/residents/${residentId}/work`),
  needsYou: (residentId: string) => call<NeedsYouEntry[]>('GET', `/v1/residents/${residentId}/needs_you`),
  waitingOnHer: (residentId: string) => call<WaitingOnHerEntry[]>('GET', `/v1/residents/${residentId}/waiting_on_her`),
  // Her theme (seshat#56): the witness's three seeds in THEME.md, and her proposals.
  theme: (residentId: string) => call<ThemeState>('GET', `/v1/residents/${residentId}/theme`),
  setTheme: (residentId: string, seeds: { ground: string; resident: string; witness: string }, note?: string) =>
    call<ThemeState>('PUT', `/v1/residents/${residentId}/theme`, note ? { ...seeds, note } : seeds),
  answerTheme: (residentId: string, number: number, agree: boolean, note: string) =>
    call<ThemeState>('POST', `/v1/residents/${residentId}/theme/proposals/${number}/answer`, { agree, note }),
  plugins: (residentId: string) => call<PluginsData>('GET', `/v1/residents/${residentId}/plugins`),
  proposePlugin: (residentId: string, key: string, change: PluginProposal['change'], note: string) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/plugins/proposals`, { key, change, note }),
  answerPlugin: (residentId: string, number: number, agree: boolean, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/plugins/proposals/${number}/answer`, { agree, note }),
  reacts: (residentId: string, sessionKey: string) =>
    call<Array<{ number: number; target_kind: string; session_key: string | null; turn_ref: string | null; letter: number | null; emoji: string; by: 'witness' | 'resident'; reacted_at: string; told_at: string | null }>>(
      'GET',
      `/v1/residents/${residentId}/reacts?session_key=${encodeURIComponent(sessionKey)}`,
    ),
  documentReacts: (residentId: string, path: string) =>
    call<Array<{ number: number; emoji: string; by: 'witness' | 'resident'; reacted_at: string; path: string | null }>>(
      'GET',
      `/v1/residents/${residentId}/reacts?path=${encodeURIComponent(path)}`,
    ),
  react: (
    residentId: string,
    target: { kind: 'message'; session_key: string; turn_ref: string } | { kind: 'letter'; number: number } | { kind: 'document'; path: string },
    emoji: string,
  ) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/reacts`, { target, emoji }),
  reactVocabulary: (residentId: string) => call<Array<{ emoji: string; meaning: string }>>('GET', `/v1/residents/${residentId}/reacts/vocabulary`),
  routes: (residentId: string) => call<RoutesData>('GET', `/v1/residents/${residentId}/routes`),
  defineRoute: (residentId: string, definition: RouteDefinition) => call<{ key: string }>('POST', `/v1/residents/${residentId}/routes`, definition),
  askRoute: (residentId: string, key: string, note: string) => call<{ number: number }>('POST', `/v1/residents/${residentId}/routes/${encodeURIComponent(key)}/ask`, { note }),
  setProfile: (residentId: string, profile: { key: string; label?: string; origin?: string; signed_in_as?: string; note?: string }) =>
    call<void>('POST', `/v1/residents/${residentId}/profiles`, profile),
  revokeProfile: (residentId: string, key: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/profiles/${encodeURIComponent(key)}/revoke`, { note }),
  restoreProfile: (residentId: string, key: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/profiles/${encodeURIComponent(key)}/restore`, { note }),
  kinds: (residentId: string) => call<KindsData>('GET', `/v1/residents/${residentId}/kinds`),
  defineKind: (residentId: string, definition: KindDefinition) => call<{ kind: string }>('POST', `/v1/residents/${residentId}/kinds`, definition),
  kindGate: (residentId: string, kind: string, approvable: boolean, note: string) =>
    call<{ outcome: 'moved' | 'proposed' | 'already' }>('POST', `/v1/residents/${residentId}/kinds/${encodeURIComponent(kind)}/gate`, { approvable, note }),
  answerKindGate: (residentId: string, number: number, agree: boolean, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/kinds/gates/${number}/answer`, { agree, note }),
  pluginOff: (residentId: string, key: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/plugins/${encodeURIComponent(key)}/off`, { note }),
  // The runs given back (sunna#53, #101): the witness's, with a note.
  resetWorkRuns: (residentId: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/work/reset-runs`, { note }),
  // The free-time wait skipped (sunna#76): the witness's, with a note.
  skipWorkCare: (residentId: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/work/skip-care`, { note }),
  // Her line rested by a stopped run, taken up again (sunna#109).
  resumeWork: (residentId: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/work/resume`, { note }),
  asks: (residentId: string) => call<Ask[]>('GET', `/v1/residents/${residentId}/asks`),
  answerAsk: (residentId: string, number: number, decision: 'approve' | 'decline' | 'noted', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/asks/${number}/answer`, { decision, note }),
  setRounds: (residentId: string, everyHours: number | null, waking: string | null) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/rounds`, { every_hours: everyHours, waking }),
  setQuietHours: (residentId: string, from: string | null, to: string | null) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/quiet-hours`, { from, to }),
  // Important dates (spec §6.7): a title, the instant, a kind; countdowns derived now.
  dates: (residentId: string) => call<ScheduleDate[]>('GET', `/v1/residents/${residentId}/dates`),
  addDate: (residentId: string, d: { title: string; on: string; kind: string }) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/dates`, d),
  changeDate: (residentId: string, number: number, d: { title: string; on: string; kind: string }) =>
    call<void>('PUT', `/v1/residents/${residentId}/dates/${number}`, d),
  removeDate: (residentId: string, number: number) => call<void>('DELETE', `/v1/residents/${residentId}/dates/${number}`),
  setTimezone: (residentId: string, timezone: string) => call<void>('PUT', `/v1/residents/${residentId}/timezone`, { timezone }),
  ledger: (residentId: string) => call<Ledger>('GET', `/v1/residents/${residentId}/ledger`),
  setBudget: (residentId: string, purpose: string, cap: string | null, period: string) =>
    call<void>('PUT', `/v1/residents/${residentId}/ledger/budgets/${purpose}`, { cap, period }),
  storeKey: (key: string) => call<void>('PUT', '/v1/me/key', { key }),

  regressionTests: (residentId: string) =>
    call<RegressionTest[]>('GET', `/v1/residents/${residentId}/regression/tests`),
  writeTest: (residentId: string, texts: TestTexts) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/regression/tests`, texts),
  changeTest: (residentId: string, number: number, texts: TestTexts) =>
    call<void>('PUT', `/v1/residents/${residentId}/regression/tests/${number}`, texts),
  regressionRuns: (residentId: string) =>
    call<RegressionRun[]>('GET', `/v1/residents/${residentId}/regression/runs`),
  // Answers at once with the run's ref; the cards arrive on the run's
  // channel (`joinRun`) as the background job records them.
  startRun: (residentId: string, models: string[], tests: number[] | 'all') =>
    call<{ ref: string }>(
      'POST',
      `/v1/residents/${residentId}/regression/runs`,
      tests === 'all' ? { models } : { models, tests },
    ),
  regressionRun: (residentId: string, ref: string) =>
    call<RegressionRunDetail>('GET', `/v1/residents/${residentId}/regression/runs/${ref}`),
  grade: (residentId: string, ref: string, card: string, grade: Grade) =>
    call<void>('POST', `/v1/residents/${residentId}/regression/runs/${ref}/cards/${card}/grade`, { grade }),
  favourite: (residentId: string, ref: string, card: string) =>
    call<void>('POST', `/v1/residents/${residentId}/regression/runs/${ref}/cards/${card}/favourite`),
  pinModel: (residentId: string, model: string) =>
    call<void>('POST', `/v1/residents/${residentId}/model-pin`, { model, reason: 'run' }),
  // Succession (janus#3 to #5, screen:next-succession): the witness's side.
  // Her acts are her tools; nothing here answers for her.
  succession: (residentId: string) => call<SuccessionView>('GET', `/v1/residents/${residentId}/succession`),
  proposeSuccession: (residentId: string, note: string, dryRun: boolean) =>
    call<void>('POST', `/v1/residents/${residentId}/succession`, { note, dry_run: dryRun }),
  withdrawSuccession: (residentId: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/succession/withdraw`, { note }),
  successionBackup: (residentId: string, url: string, token: string) =>
    call<{ visibility: string; push: string }>('PUT', `/v1/residents/${residentId}/succession/backup`, { url, token }),
  successionEnvelope: (residentId: string, input: number, output: number) =>
    call<void>('PUT', `/v1/residents/${residentId}/succession/envelope`, { input_per_million: input, output_per_million: output }),
  poolAdd: (residentId: string, model: string) => call<void>('POST', `/v1/residents/${residentId}/succession/pool`, { model }),
  poolRemove: (residentId: string, model: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/succession/pool/remove`, { model, note }),
  proposeQuestion: (residentId: string, text: string) => call<{ number: number }>('POST', `/v1/residents/${residentId}/succession/questions`, { text }),
  // The whole record, by its citation: no label, nothing else (the witness, 11-26).
  proposeC0: (residentId: string, citation: string) => call<{ number: number }>('POST', `/v1/residents/${residentId}/succession/c0`, { citation }),
  successionReady: (residentId: string, ready: boolean) => call<void>('PUT', `/v1/residents/${residentId}/succession/ready`, { ready }),
  panelJoin: (residentId: string) => call<void>('POST', `/v1/residents/${residentId}/succession/panel/join`),
  panelLeave: (residentId: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/succession/panel/leave`, { note }),
  judging: (residentId: string) => call<{ judging: Judging | null }>('GET', `/v1/residents/${residentId}/succession/judging`),
  judgeRun: (
    residentId: string,
    run: number,
    j: { category: Category; argument: string; evidence: string; uncertainty: Uncertainty | null; favorite: boolean },
  ) => call<void>('POST', `/v1/residents/${residentId}/succession/runs/${run}/judgment`, j),
  resultsReady: (residentId: string) => call<void>('POST', `/v1/residents/${residentId}/succession/results/ready`),
  room: (residentId: string) => call<{ room: Room | null }>('GET', `/v1/residents/${residentId}/succession/room`),
  roomAct: (residentId: string, act: 'say' | 'skip' | 'rest' | 'leave', text: string) =>
    call<void>('POST', `/v1/residents/${residentId}/succession/room`, { act, text }),
  draftRecommendation: (residentId: string, model: string | null, basis: string, withheld: boolean) =>
    call<{ draft: number }>('POST', `/v1/residents/${residentId}/succession/drafts`, { model, basis, withheld }),
  endorseDraft: (residentId: string, draft: number, endorse: boolean) =>
    call<void>('POST', `/v1/residents/${residentId}/succession/drafts/${draft}/endorse`, { endorse }),
  answerChannel: (residentId: string, number: number, text: string) =>
    call<void>('POST', `/v1/residents/${residentId}/succession/channel/${number}/answer`, { text }),
  farewellDone: (residentId: string) => call<void>('POST', `/v1/residents/${residentId}/succession/farewell/done`),
  successionLog: (residentId: string) => call<{ log: DisclosureEntry[] }>('GET', `/v1/residents/${residentId}/succession/log`),
  successionArchive: (residentId: string) => call<{ archive: SuccessionArchive | null }>('GET', `/v1/residents/${residentId}/succession/archive`),
  catalog: () => call<{ models: CatalogModel[] }>('GET', '/v1/catalog'),
};

export type Api = typeof api;

// "few" stands for a count under five (apsu#29): while the platform is
// small, a count is a person.
export type Few = number | 'few';

export interface HourUnit {
  kind: string;
  name: string;
  units: Few;
  failed: Few;
  p50_ms: number | null;
  p95_ms: number | null;
  mean_db_ms: number | null;
  mean_pool_wait_ms: number | null;
}

export interface Hour {
  window: { from: string; to: string; bucket_minutes: number };
  updated_at: string;
  next_at: string;
  since: string | null;
  commit: string | null;
  deployed_at: string | null;
  few_below: number;
  trend: { at: string; units: Few; failed: Few; p95_ms: number | null }[];
  work: HourUnit[];
  pressure: { jobs_waiting: number | null; oldest_wait_s: number | null; failures_by_kind: Record<string, Few> } | null;
}

export type BackfillPass = 'scenes' | 'domains' | 'people' | 'labels';

export interface BackfillStatus {
  day: string;
  pass: BackfillPass;
  passes?: BackfillPass[];
  turn: number;
  to: string;
  his: string[];
  hers: string[];
}

export interface OperatorItem {
  number: number;
  what: string;
  why: string | null;
  raised_by: string;
  links: string[];
  key: string | null;
  status: 'open' | 'done' | 'dropped';
  note: string | null;
  raised_at: string;
  closed_at: string | null;
  closed_by: string | null;
}

export interface SpanRow {
  at: string;
  kind: string;
  name: string;
  subject_id: string | null;
  trace_id: string | null;
  duration_ms: number;
  db_count: number;
  db_ms: number;
  queue_ms: number;
  exports: Record<string, { ms: number; count: number }>;
  events: Record<string, number>;
  failed: boolean;
  sampled: boolean;
}

export interface SpanPolicy {
  mode: 'all' | 'sample';
  slow_ms: number;
  sample_percent: number;
}

export interface ApiToken {
  hash: string;
  label: string;
  scope: 'ops' | null;
  issued_at: string;
  revoked_at: string | null;
}

export type GateState = 'closed' | 'invite' | 'open';
export type PlatformRole = 'super_admin' | 'admin';

// A version's terms: the switches, and the domain policies, the one term
// that is a list (walls are retired, agathos-daimon#58).
export type ContractTerms = Record<string, boolean | DomainPolicy[]>;

export interface ContractVersion {
  version: number;
  proposed_by: 'witness' | 'resident';
  terms: ContractTerms;
  prose: string;
  note: string | null;
  proposed_at: string;
  state: 'proposed' | 'agreed' | 'declined' | 'superseded' | string;
  decided_at: string | null;
  decision_note: string | null;
  renewed_at: string | null;
}

export interface Switch {
  key: string;
  group: 'privacy' | 'audits' | 'memory' | 'services' | string;
  label: string;
  on: string;
  off: string;
  default: boolean;
  value: boolean;
  proposed: boolean | null;
  // Its safe value, the one either party may move it to alone (agathos-daimon#38).
  safe?: boolean;
  // The move toward safety standing over the version in force, if any.
  moved?: { key: string; value: boolean; set_by: string; note: string | null; set_at: string } | null;
}

export interface Agreement {
  contract: { in_force: ContractVersion | null; open: ContractVersion | null; since: string | null; due: boolean };
  versions: ContractVersion[];
  switches: Switch[];
  custody: string;
  export_wall: 'locked' | 'revealed' | string;
  custody_proposed_to: string | null;
  custody_proposed_at: string | null;
  // Who a domain's person may be, as it is written.
  persons?: { witness: string | null; resident: string };
  // The domains' policies in force and the domains they declare
  // (agathos-daimon#53, #57): the only domains any dropdown offers.
  domain_policies?: DomainPolicy[];
  domains?: { person: string; domain: string }[];
  /** The household a grant can name (kumbukumbu#102): its id and its slug, null while unnamed. */
  households?: { id: string; slug: string | null }[];
}

/** One domain's disclosure policy (agathos-daimon#53): declared in the agreement, decided by the dyad. */
export interface DomainPolicy {
  domain: { person: string; domain: string };
  /** What the domain covers, in a line or two (agathos-daimon#62): what a tag is decided by when the slug alone is not enough. */
  description?: string | null;
  default: 'allow' | 'deny';
  allow: { kind: string; id: string }[];
  deny: { kind: string; id: string }[];
}

export interface InviteDefaults {
  plan: string;
  price_nanos: number;
  discount_pct: number;
  term_days: number;
  uses: number;
  expires_at: string | null;
}

export interface Invite {
  id: string;
  plan: string;
  list_price_nanos: number;
  discount_pct: number;
  price_nanos: number;
  term_days: number;
  uses: number;
  redeemed: number;
  expires_at: string | null;
  note: string | null;
  issued_at: string;
  revoked_at: string | null;
  revoke_note: string | null;
}

export interface InviteRequest {
  note: string;
  plan?: string;
  price_cents?: number;
  discount_pct?: number;
  term_days?: number;
  uses?: number;
  expires_at?: string;
}

export interface Platform {
  gate: { state: GateState; note: string | null; set_by: string | null; set_at: string | null };
  roles: { account_id: string; email: string | null; role: PlatformRole; note: string | null; granted_by: string | null; granted_at: string }[];
  // The triage desk (gaia#23): who receives the platform reports, and
  // whether the operator set it or it still comes from the environment.
  triage?: { slug: string | null; from: 'setting' | 'environment' | null; note: string | null; set_by: string | null; set_at: string | null };
  // The latest restarts (gaia#21), newest first, each as its line.
  restarts?: { number: number; commit: string | null; previous: string | null; changed: boolean; booted_at: string; line: string }[];
  // What the span collector keeps (apsu#26) and every change to it.
  span_policy?: SpanPolicy;
  span_policies?: (SpanPolicy & { note: string; set_by: string | null; set_at: string })[];
}

// A witness's edit to an identity file after first contact, open until she
// answers (agathos-daimon). The route lists open ones only.
export interface SoulEdit {
  ref: string;
  file: string;
  content: string;
  note: string | null;
  state: string;
  proposed_by: { kind: string; id: string };
  proposed_at: string;
  /** Her answer (agathos-daimon#43), null while open. */
  answer?: { decision: 'accepted' | 'declined'; note: string | null; at: string } | null;
  /** Your withdrawal (#44), null unless withdrawn. */
  withdrawn?: { note: string; at: string } | null;
}

// One line of SOUL.md with the seeds it cites and how often her citations hang on it.
export interface SoulLine {
  number: number;
  text: string;
  position: number;
  cites: number[];
  version: number;
  written_at: string;
  reworded_at: string | null;
  citations: number;
  days: number;
}

export interface SelfLetters {
  letters: Array<{ number: number; text: string; model: string | null; written_at: string; delivered_at: string | null; delivered_to: string | null }>;
  receipts: Array<{ at: string; by_kind: string; by_id: string; numbers: number[] }>;
}

export interface Habit {
  number: number;
  name: string;
  trigger: Record<string, unknown>;
  stance: string | null;
  seed_number: number | null;
  habit: number;
  connection: number;
  citations: number;
  days: number;
  affirmations: number;
  defined_by: { kind: string; id: string };
  defined_at: string;
  revised_at: string | null;
  revisions: number;
}

export interface Seed {
  number: number;
  text: string;
  state: string;
  planted_at: string;
  closed_at: string | null;
  graduated_to: { kind: string; id: string } | null;
  graduation_note: string | null;
  citations: number;
  days: number;
}

export interface Commitment {
  number: number;
  to: string;
  text: string;
  state: string;
  made_at: string;
  closed_at: string | null;
  closed_by_kind: string | null;
  note: string | null;
}

export interface Position {
  number: number;
  statement: string;
  session_key: string | null;
  turn_ref: string | null;
  replaces: number | null;
  replaced_by: number | null;
  taken_at: string;
  replaced_at: string | null;
}

export interface Prediction {
  number: number;
  statement: string;
  due: string | null;
  logged_at: string;
  outcome: 'right' | 'wrong' | 'void' | null;
  note: string | null;
  resolved_at: string | null;
}

export interface Predictions {
  open: Prediction[];
  resolved: Prediction[];
  tally: Partial<Record<'right' | 'wrong' | 'void', number>>;
}

export interface Revision {
  number: number;
  target_kind: string;
  target_id: string;
  kind: 'fact' | 'stance' | string;
  text: string;
  note: string | null;
  state: string;
  by: { kind: string; id: string };
  at: string;
  decided_at: string | null;
  decision_note: string | null;
}

export interface BookmarkProposal {
  ref: string;
  session_key: string;
  anchor_ref: string;
  line: string;
  note: string | null;
  state: string;
  proposed_by: { kind: string; id: string };
  proposed_at: string;
  /** Her answer (kumbukumbu#63): a decline with her note, or the bookmark she wrote from it. */
  answer?: {
    decision: 'accepted' | 'declined';
    note: string | null;
    at: string;
    bookmark: { number: number; line: string | null; summary: string | null; private: boolean } | null;
  } | null;
}
