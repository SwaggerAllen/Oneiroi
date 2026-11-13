import type { Gift } from '../screens/creation-flow/CreationFlow';
import type { ReportDetail } from '../screens/more/Reports';
import type {
  Adapter,
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
  | { type: 'transcript'; ref: { session_key: string; turn_ref: string; cursor: string }; title: string; snippet: string; at: string | null; score: number | null }
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
  signUp: (email: string, password: string, code: string | null) =>
    call<{ account_id: string; email: string }>('POST', '/v1/door/sign-up', { email, password, ...(code ? { code } : {}) }),
  me: () =>
    call<{ email: string; residents: string[]; roles?: string[]; key?: { present: boolean }; github?: { present: boolean; stored_at: string | null } }>('GET', '/v1/me'),
  storeGithubToken: (token: string) => call<void>('PUT', '/v1/me/github-token', { token }),
  revokeGithubToken: () => call<void>('DELETE', '/v1/me/github-token'),
  // The operator's surface (gaia#16): the front door and the platform roles.
  platform: () => call<Platform>('GET', '/v1/platform'),
  setGate: (state: GateState, note: string) => call<Platform['gate']>('PUT', '/v1/platform/gate', { state, note }),
  setTriage: (slug: string | null, note: string) => call<NonNullable<Platform['triage']>>('PUT', '/v1/platform/triage', { slug, note }),
  grantRole: (email: string, role: PlatformRole, note: string) => call<void>('POST', '/v1/platform/roles', { email, role, note }),
  revokeRole: (accountId: string, role: PlatformRole, note: string) =>
    call<void>('DELETE', '/v1/platform/roles', { account_id: accountId, role, note }),
  // Your agreement and who looks after the resident (agathos-daimon#34, spec §6.12).
  agreement: (residentId: string) => call<Agreement>('GET', `/v1/residents/${residentId}/agreement`),
  proposeContract: (residentId: string, terms: Record<string, boolean>, prose: string, note: string) =>
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
  importResident: (url: string, name: string | null, slug: string | null) =>
    call<Resident>('POST', '/v1/residents/import', { url, ...(name ? { name } : {}), ...(slug ? { slug } : {}) }),
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
  submit: (residentId: string, key: string, text: string, clientRef: string) =>
    call<{ turn_ref: string; state: 'running' | 'queued' | 'duplicate'; ahead?: number }>(
      'POST',
      `/v1/residents/${residentId}/sessions/${key}/turns`,
      { text, client_ref: clientRef },
    ),
  // The turns that failed and are not yet resolved: read back on return
  // so a failure broadcast while away is still seen (brain#54).
  captureFailures: (residentId: string) =>
    call<{ turn_ref: string; session_key: string; reason: string; failed_at: string }[]>(
      'GET',
      `/v1/residents/${residentId}/capture-failures`,
    ),
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
    call<{ path: string; current: string | null; versions: DocumentVersion[] }>('GET', `/v1/residents/${residentId}/library/versions/${path}`),
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
  feedbackReport: (n: number) => call<ReportDetail>('GET', `/v1/platform/feedback/${n}`),
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
  addWork: (residentId: string, what: string, doneWhen: string) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/work`, { what, done_when: doneWhen }),
  moveWork: (residentId: string, number: number, status: string, blockedOn: string | null, note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/work/${number}/status`, { status, blocked_on: blockedOn, note }),
  // Held for the witness (sunna#54): the ask says what is needed of him; release is moveWork back to open.
  holdWork: (residentId: string, number: number, ask: string, note: string | null) =>
    call<void>('POST', `/v1/residents/${residentId}/work/${number}/status`, { status: 'held', ask, note }),
  orderWork: (residentId: string, order: number[]) => call<void>('PUT', `/v1/residents/${residentId}/work/order`, { order }),
  armWork: (residentId: string) => call<void>('POST', `/v1/residents/${residentId}/work/arm`),
  disarmWork: (residentId: string) => call<void>('POST', `/v1/residents/${residentId}/work/disarm`),
  // The day's runs given back (sunna#53): the witness's, with a note.
  resetWorkRuns: (residentId: string, note: string) => call<void>('POST', `/v1/residents/${residentId}/work/reset-runs`, { note }),
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
};

export type Api = typeof api;

export type GateState = 'closed' | 'invite' | 'open';
export type PlatformRole = 'super_admin' | 'admin';

export interface ContractVersion {
  version: number;
  proposed_by: 'witness' | 'resident';
  terms: Record<string, boolean>;
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
