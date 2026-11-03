import type {
  ApiError,
  Bookmark,
  ContextPreview,
  Block,
  CorrespondenceMessage,
  Grade,
  HouseLetter,
  IndexNow,
  Injection,
  Ledger,
  RegressionRun,
  RegressionRunDetail,
  RegressionTest,
  Reply,
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
// which is what the Origin check reads (gaia #5).
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
  // that reads like a bug and loses the status (brain #45).
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
  me: () => call<{ email: string; residents: string[] }>('GET', '/v1/me'),
  residents: () => call<Resident[]>('GET', '/v1/residents'),
  socketToken: () => call<{ token: string }>('POST', '/v1/me/socket-token'),

  mainSession: (residentId: string) =>
    call<{ key: string }>('POST', `/v1/residents/${residentId}/sessions`, { kind: 'main' }),
  // Last spoken in first, each named by the server (kumbukumbu #40).
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
  // Taken at once under the client's ref (brain #45); the turn arrives on the channel.
  submit: (residentId: string, key: string, text: string, clientRef: string) =>
    call<{ turn_ref: string; state: 'running' | 'queued' | 'duplicate'; ahead?: number }>(
      'POST',
      `/v1/residents/${residentId}/sessions/${key}/turns`,
      { text, client_ref: clientRef },
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
  letters: (residentId: string) => call<HouseLetter[]>('GET', `/v1/residents/${residentId}/letters`),
  schedule: (residentId: string) => call<ScheduleToday>('GET', `/v1/residents/${residentId}/schedule`),
  setFreeTime: (residentId: string, times: string[]) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/free-time`, { times }),
  addCheckin: (residentId: string, label: string, time: string) =>
    call<{ key: string }>('POST', `/v1/residents/${residentId}/schedule/checkins`, { label, time }),
  changeCheckin: (residentId: string, key: string, label: string, time: string) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/checkins/${key}`, { label, time }),
  deleteCheckin: (residentId: string, key: string) =>
    call<void>('DELETE', `/v1/residents/${residentId}/schedule/checkins/${key}`),
  setQuietHours: (residentId: string, from: string | null, to: string | null) =>
    call<void>('PUT', `/v1/residents/${residentId}/schedule/quiet-hours`, { from, to }),
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
