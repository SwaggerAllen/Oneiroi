import type {
  ApiError,
  Bookmark,
  ContextPreview,
  Grade,
  IndexNow,
  Injection,
  Ledger,
  Message,
  RegressionRun,
  RegressionRunDetail,
  RegressionTest,
  Resident,
  Session,
  Tag,
  TestTexts,
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
  const json = text ? (JSON.parse(text) as unknown) : null;
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
  transcript: (residentId: string, key: string) =>
    call<{ session: Session; messages: Message[] }>(
      'GET',
      `/v1/residents/${residentId}/sessions/${key}`,
    ),
  send: (residentId: string, key: string, text: string) =>
    call<Turn>('POST', `/v1/residents/${residentId}/sessions/${key}/turns`, { text }),
  injections: (residentId: string, turnRef: string) =>
    call<Injection[]>('GET', `/v1/residents/${residentId}/turns/${turnRef}/context`),

  // A POST that writes nothing: the draft rides the body, never the URL.
  preview: (residentId: string, key: string, text: string) =>
    call<ContextPreview>('POST', `/v1/residents/${residentId}/sessions/${key}/preview`, { text }),

  indexNow: (residentId: string) => call<IndexNow>('GET', `/v1/residents/${residentId}/index`),
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
