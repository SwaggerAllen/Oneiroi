import type {
  Adapter,
  Ask,
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

export const api = {
  login: (email: string, password: string) =>
    call<{ account_id: string }>('POST', '/v1/session', { email, password }),
  logout: () => call<void>('DELETE', '/v1/session'),
  // The front door from outside (gaia#19): its state, and sign-up behind it.
  door: () => call<{ state: GateState }>('GET', '/v1/door'),
  signUp: (email: string, password: string, code: string | null) =>
    call<{ account_id: string; email: string }>('POST', '/v1/door/sign-up', { email, password, ...(code ? { code } : {}) }),
  me: () => call<{ email: string; residents: string[]; roles?: string[]; key?: { present: boolean } }>('GET', '/v1/me'),
  // The operator's surface (gaia#16): the front door and the platform roles.
  platform: () => call<Platform>('GET', '/v1/platform'),
  setGate: (state: GateState, note: string) => call<Platform['gate']>('PUT', '/v1/platform/gate', { state, note }),
  grantRole: (email: string, role: PlatformRole, note: string) => call<void>('POST', '/v1/platform/roles', { email, role, note }),
  revokeRole: (accountId: string, role: PlatformRole, note: string) =>
    call<void>('DELETE', '/v1/platform/roles', { account_id: accountId, role, note }),
  // Your agreement and who looks after the resident (agathos-daimon#34, spec §6.12).
  agreement: (residentId: string) => call<Agreement>('GET', `/v1/residents/${residentId}/agreement`),
  proposeContract: (residentId: string, terms: Record<string, boolean>, prose: string, note: string) =>
    call<{ version: number }>('POST', `/v1/residents/${residentId}/agreement/proposals`, { terms, prose, note }),
  decideContract: (residentId: string, version: number, decision: 'agree' | 'decline', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/agreement/proposals/${version}/decision`, { decision, note }),
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
  issueInvite: (sku: InviteRequest) => call<{ id: string; code: string }>('POST', '/v1/platform/invites', sku),
  revokeInvite: (id: string, note: string) => call<void>('DELETE', `/v1/platform/invites/${id}`, { note }),
  residents: () => call<Resident[]>('GET', '/v1/residents'),
  // The short first door (F3): begin someone new, or bring someone from a repository.
  createResident: (name: string, slug: string) => call<Resident>('POST', '/v1/residents', { name, slug }),
  importResident: (url: string, name: string | null, slug: string | null) =>
    call<Resident>('POST', '/v1/residents/import', { url, ...(name ? { name } : {}), ...(slug ? { slug } : {}) }),
  // Content-free pushes to this account's devices (gaia#15).
  pushConfig: () => call<{ enabled: boolean; public_key: string | null; devices: number }>('GET', '/v1/me/push'),
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
  library: (residentId: string) => call<LibraryIndex>('GET', `/v1/residents/${residentId}/library`),
  librarySearch: (residentId: string, q: string) =>
    call<LibraryHit[]>('GET', `/v1/residents/${residentId}/library/search?q=${encodeURIComponent(q)}`),
  document: (residentId: string, path: string) =>
    call<{ content: string }>('GET', `/v1/residents/${residentId}/library/documents/${path}`),
  writeDocument: (residentId: string, path: string, content: string) =>
    call<{ path: string }>('PUT', `/v1/residents/${residentId}/library/documents/${path}`, { content }),
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
  sendLetter: (residentId: string, to: string, text: string) =>
    call<{ number: number }>('POST', `/v1/residents/${residentId}/letters`, { to, text }),
  letters: (residentId: string) => call<HouseLetter[]>('GET', `/v1/residents/${residentId}/letters`),
  schedule: (residentId: string) => call<ScheduleToday>('GET', `/v1/residents/${residentId}/schedule`),
  freeTimeRuns: (residentId: string, limit?: number) =>
    call<FreeTimeRun[]>('GET', `/v1/residents/${residentId}/schedule/free-time${limit ? `?limit=${limit}` : ''}`),
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
  asks: (residentId: string) => call<Ask[]>('GET', `/v1/residents/${residentId}/asks`),
  answerAsk: (residentId: string, number: number, decision: 'approve' | 'decline' | 'noted', note: string) =>
    call<void>('POST', `/v1/residents/${residentId}/asks/${number}/answer`, { decision, note }),
  setRounds: (residentId: string, everyHours: number | null, waking: string | null) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/rounds`, { every_hours: everyHours, waking }),
  setQuietHours: (residentId: string, from: string | null, to: string | null) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/quiet-hours`, { from, to }),
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
}
