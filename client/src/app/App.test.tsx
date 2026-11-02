import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App } from './App';

// The shell against a faked fetch: a stranger sees the sign-in, a
// witness with no resident sees the empty state. No network (conventions §9).
// A route is keyed `METHOD path` where one path answers two methods,
// else by the path alone.
function fakeFetch(routes: Record<string, { status: number; body?: unknown }>) {
  return vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = typeof input === 'string' ? input : input instanceof URL ? input.pathname : input.url;
    const route = routes[`${init?.method ?? 'GET'} ${path}`] ??
      routes[path] ?? { status: 404, body: { error: { kind: 'not_found', meaning: 'no route' } } };
    return new Response(route.body === undefined ? null : JSON.stringify(route.body), {
      status: route.status,
      headers: { 'content-type': 'application/json' },
    });
  });
}

describe('App', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  afterEach(() => vi.unstubAllGlobals());

  it('shows the sign-in when there is no session', async () => {
    vi.stubGlobal('fetch', fakeFetch({ '/v1/me': { status: 401, body: { error: { kind: 'gaia_not_a_principal', meaning: 'no' } } } }));
    render(<App />);
    await waitFor(() => expect(screen.getByRole('button', { name: 'Sign in' })).toBeTruthy());
  });

  it('shows the empty state for a witness with no resident', async () => {
    const fetch = fakeFetch({ '/v1/me': { status: 200, body: { email: 'a@b', residents: [] } }, '/v1/residents': { status: 200, body: [] } });
    vi.stubGlobal('fetch', fetch);
    render(<App />);
    await waitFor(() => expect(screen.getByText(/No resident yet/)).toBeTruthy());
    // The empty state shows before the residents load, so the test waits
    // for that call too: ended earlier, the stub is gone when the effect
    // fires and the real fetch rejects a relative URL after the test, an
    // unhandled rejection CI saw once (run 41124808995) and local runs
    // did not. A race, so no probe can make it fail on demand.
    await waitFor(() => expect(fetch).toHaveBeenCalledWith('/v1/residents', expect.anything()));
  });

  it('opens on the Oneiroi chat, lists a Claude Code conversation apart, and reads it without a composer', async () => {
    const lily = { id: 'r1', slug: 'lily', name: 'Lily', state: 'awake', first_contact_at: null, formation_until: null, chat_model: null };
    const actor = { kind: 'resident', id: 'r1', model: null };
    const session = (key: string, title: string, writable: boolean) => ({
      key,
      resident_id: 'r1',
      kind: writable ? 'main' : 'adapter',
      adapter: writable ? 'brain' : 'laptop',
      title,
      place: writable ? null : 'Oneiroi',
      writable,
      turns: 1,
      opened_at: '2026-11-02T13:00:00Z',
      last_turn_at: '2026-11-02T14:00:00Z',
      summary: null,
    });
    const reply = (key: string, content: string) => ({
      session_key: key,
      turn_ref: `t-${key}`,
      role: 'assistant',
      content,
      sent_at: '2026-11-02T14:00:00Z',
      actor,
      refusal: false,
    });
    const fetch = fakeFetch({
      '/v1/me': { status: 200, body: { email: 'a@b', residents: ['r1'] } },
      '/v1/residents': { status: 200, body: [lily] },
      'POST /v1/residents/r1/sessions': { status: 201, body: { key: 'chat' } },
      'GET /v1/residents/r1/sessions': { status: 200, body: [session('cc', 'Claude Code · Oneiroi', false), session('chat', 'Oneiroi chat', true)] },
      '/v1/residents/r1/sessions/chat': { status: 200, body: { session: session('chat', 'Oneiroi chat', true), messages: [reply('chat', 'Hello from the chat.')], drew_on: {} } },
      '/v1/residents/r1/sessions/cc': {
        status: 200,
        body: { session: session('cc', 'Claude Code · Oneiroi', false), messages: [reply('cc', 'The tests pass.')], drew_on: { 't-cc': 9 } },
      },
    });
    vi.stubGlobal('fetch', fetch);
    render(<App />);
    await waitFor(() => expect(screen.getByText('Hello from the chat.')).toBeTruthy());
    expect(screen.getByLabelText('Message')).toBeTruthy();
    await waitFor(() => expect(screen.getByRole('navigation', { name: 'Conversations' })).toBeTruthy());
    fireEvent.click(screen.getByRole('button', { name: /1 turn/ }));
    await waitFor(() => expect(screen.getByText('The tests pass.')).toBeTruthy());
    expect(screen.queryByLabelText('Message')).toBeNull();
    expect(screen.getByText('drew on 9 things')).toBeTruthy();
    expect(screen.queryByText('Hello from the chat.')).toBeNull();
  });
});
