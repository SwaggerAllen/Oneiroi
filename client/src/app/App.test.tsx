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
      // The chat reads a conversation a page at a time, newest first.
      '/v1/residents/r1/sessions/chat?limit=50': {
        status: 200,
        body: { session: session('chat', 'Oneiroi chat', true), messages: [reply('chat', 'Hello from the chat.')], drew_on: {}, more: false },
      },
      '/v1/residents/r1/sessions/cc?limit=50': {
        status: 200,
        body: { session: session('cc', 'Claude Code · Oneiroi', false), messages: [reply('cc', 'The tests pass.')], drew_on: { 't-cc': 9 }, more: false },
      },
    });
    vi.stubGlobal('fetch', fetch);
    render(<App />);
    await waitFor(() => expect(screen.getByText('Hello from the chat.')).toBeTruthy());
    expect(screen.getByLabelText('Message')).toBeTruthy();
    // The list is a button in the top bar with the count of the others.
    await waitFor(() => expect(screen.getByRole('button', { name: 'Conversations · 1' })).toBeTruthy());
    fireEvent.click(screen.getByRole('button', { name: 'Conversations · 1' }));
    fireEvent.click(screen.getByRole('button', { name: /1 turn/ }));
    await waitFor(() => expect(screen.getByText('The tests pass.')).toBeTruthy());
    expect(screen.queryByLabelText('Message')).toBeNull();
    expect(screen.getByText('drew on 9 things')).toBeTruthy();
    expect(screen.queryByText('Hello from the chat.')).toBeNull();
  });

  // Client #13: a phone suspends the page's stream while it is away, so
  // coming back reads the conversation again and joins the stream anew.
  it('reads the open conversation again and asks for a fresh stream when the page comes back', async () => {
    const lily = { id: 'r1', slug: 'lily', name: 'Lily', state: 'awake', first_contact_at: null, formation_until: null, chat_model: null };
    const actor = { kind: 'resident', id: 'r1', model: null };
    const session = {
      key: 'chat',
      resident_id: 'r1',
      kind: 'main',
      adapter: 'brain',
      title: 'Oneiroi chat',
      place: null,
      writable: true,
      turns: 1,
      opened_at: '2026-11-02T13:00:00Z',
      last_turn_at: '2026-11-02T14:00:00Z',
      summary: null,
    };
    const reply = (n: number, content: string) => ({
      session_key: 'chat',
      turn_ref: `t-${n}`,
      role: 'assistant',
      content,
      sent_at: `2026-11-02T14:0${n}:00Z`,
      cursor: `c${n}`,
      actor,
      refusal: false,
    });
    const page = { session, messages: [reply(1, 'Before you left.')], drew_on: {}, more: false };
    const fetch = fakeFetch({
      '/v1/me': { status: 200, body: { email: 'a@b', residents: ['r1'] } },
      '/v1/residents': { status: 200, body: [lily] },
      'POST /v1/residents/r1/sessions': { status: 201, body: { key: 'chat' } },
      'GET /v1/residents/r1/sessions': { status: 200, body: [session] },
      '/v1/residents/r1/sessions/chat?limit=50': { status: 200, body: page },
    });
    vi.stubGlobal('fetch', fetch);
    render(<App />);
    await waitFor(() => expect(screen.getByText('Before you left.')).toBeTruthy());
    const tokens = () => fetch.mock.calls.filter(([url]) => String(url).endsWith('/socket-token')).length;
    await waitFor(() => expect(tokens()).toBe(1));

    // A turn landed while the page was away; nothing on the stream said so.
    page.messages = [reply(1, 'Before you left.'), reply(2, 'While you were away.')];
    window.dispatchEvent(new Event('focus'));

    await waitFor(() => expect(screen.getByText('While you were away.')).toBeTruthy());
    // The stream was down (no token here), so it is joined again, freshly.
    await waitFor(() => expect(tokens()).toBe(2));
  });

  // Brain #45: a message is never lost on the wire. It goes under the
  // client's own ref; a failed request (here Render's HTML 502) keeps it,
  // marked not sent; Retry sends it again under the same ref, so the
  // server can tell a retry from a new message.
  it('keeps a message the server never took and sends it again under the same ref', async () => {
    const lily = { id: 'r1', slug: 'lily', name: 'Lily', state: 'awake', first_contact_at: null, formation_until: null, chat_model: null };
    const page = { session: { key: 'chat', title: 'Oneiroi chat', writable: true }, messages: [], drew_on: {}, more: false };
    const sent: Array<{ text: string; client_ref: string }> = [];
    let turns = 0;
    const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const path = typeof input === 'string' ? input : input.toString();
      const json = (status: number, body: unknown) =>
        new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
      if (path === '/v1/me') return json(200, { email: 'a@b', residents: ['r1'] });
      if (path === '/v1/residents') return json(200, [lily]);
      if (path === '/v1/residents/r1/sessions' && init?.method === 'POST') return json(201, { key: 'chat' });
      if (path === '/v1/residents/r1/sessions') return json(200, []);
      if (path.startsWith('/v1/residents/r1/sessions/chat?')) return json(200, page);
      if (path === '/v1/residents/r1/sessions/chat/turns') {
        sent.push(JSON.parse(String(init?.body)) as { text: string; client_ref: string });
        turns += 1;
        return turns === 1
          ? new Response('<html>502 Bad Gateway</html>', { status: 502, headers: { 'content-type': 'text/html' } })
          : json(202, { turn_ref: sent[0].client_ref, state: 'running', ahead: 0 });
      }
      return json(404, { error: { kind: 'not_found', meaning: 'no route' } });
    });
    vi.stubGlobal('fetch', fetch);
    render(<App />);
    await waitFor(() => expect(screen.getByLabelText('Message')).toBeTruthy());
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'hello' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await waitFor(() => expect(screen.getByLabelText('Not sent').textContent).toContain('hello'));
    fireEvent.click(screen.getByRole('button', { name: 'Retry' }));
    await waitFor(() => expect(screen.getByLabelText('Sending').textContent).toContain('delivered'));
    expect(sent).toHaveLength(2);
    expect(sent[0].client_ref).toMatch(/^[A-Za-z0-9_-]{8,64}$/);
    expect(sent[1]).toEqual(sent[0]);
  });

  it('saves the reader\'s allowlists on Connections, keeps a refused draft with the server\'s words, and asks research', async () => {
    const lily = { id: 'r1', slug: 'lily', name: 'Lily', state: 'awake', first_contact_at: null, formation_until: null, chat_model: null };
    const fetch = fakeFetch({
      '/v1/me': { status: 200, body: { email: 'a@b', residents: ['r1'] } },
      '/v1/residents': { status: 200, body: [lily] },
      '/v1/residents/r1/adapters': { status: 200, body: [] },
      'GET /v1/residents/r1/reader': { status: 200, body: { scrape: ['https://substack.com'], research: [], set_at: null } },
      'PUT /v1/residents/r1/reader': {
        status: 422,
        body: { error: { kind: 'xenia_sites_invalid', meaning: 'example.org/a is not an origin.', remedy: 'Give a scheme and host, or *.' } },
      },
      'GET /v1/residents/r1/research': { status: 200, body: [] },
      'POST /v1/residents/r1/research': { status: 201, body: { number: 1 } },
    });
    vi.stubGlobal('fetch', fetch);
    location.hash = 'connections';
    try {
      render(<App />);
      const research = (await screen.findByLabelText(/^Research/)) as HTMLTextAreaElement;
      fireEvent.change(research, { target: { value: 'example.org/a' } });
      fireEvent.click(screen.getByRole('button', { name: 'Save' }));
      await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('is not an origin'));
      expect((screen.getByLabelText(/^Research/) as HTMLTextAreaElement).value).toBe('example.org/a');
      const put = fetch.mock.calls.find(([, init]) => init?.method === 'PUT');
      expect(JSON.parse(put?.[1]?.body as string)).toEqual({ scrape: ['https://substack.com'], research: ['example.org/a'] });
      fireEvent.change(screen.getByLabelText('Question'), { target: { value: 'When do herons fish?' } });
      fireEvent.click(screen.getByRole('button', { name: 'Ask' }));
      await waitFor(() => expect(fetch.mock.calls.some(([, init]) => init?.method === 'POST' && String(init.body).includes('herons'))).toBe(true));
      const post = fetch.mock.calls.find(([, init]) => init?.method === 'POST' && String(init.body).includes('herons'));
      expect(JSON.parse(post?.[1]?.body as string)).toEqual({ question: 'When do herons fish?' });
    } finally {
      location.hash = '';
    }
  });

  // Free time, remembered (brain#53): read beside the schedule and again
  // on coming back to the page (client#13).
  it('reads free time remembered on the Schedule screen, and again when the page comes back', async () => {
    const lily = { id: 'r1', slug: 'lily', name: 'Lily', state: 'awake', first_contact_at: null, formation_until: null, chat_model: null };
    const today = {
      day: '2026-11-03',
      now: '2026-11-03T15:00:00-08:00',
      timezone: 'America/Los_Angeles',
      checkins: [],
      firings: [],
      last: null,
      next: null,
      free_times: [{ time: '14:30', today: 'ran' }],
      free_time_last: { day: '2026-11-03', outcome: 'ran' },
      quiet: null,
      dates: [],
    };
    const run = { day: '2026-11-03', slot: '14:30', outcome: 'ran', session_key: 'f1', at: '2026-11-03T22:40:00Z', turns: 4, did: [{ tool: 'bookmark_add', result: 'Bookmarked as #96.' }] };
    const fetch = fakeFetch({
      '/v1/me': { status: 200, body: { email: 'a@b', residents: ['r1'] } },
      '/v1/residents': { status: 200, body: [lily] },
      '/v1/residents/r1/schedule': { status: 200, body: today },
      'GET /v1/residents/r1/schedule/free-time': { status: 200, body: [run] },
    });
    vi.stubGlobal('fetch', fetch);
    location.hash = 'schedule';
    try {
      render(<App />);
      await waitFor(() => expect(screen.getByText('Bookmarked as #96.')).toBeTruthy());
      expect(screen.getByRole('list', { name: 'Free-time runs' }).textContent).toMatch(/2026-11-03 14:30 · ran · 4 turns/);
      const reads = () => fetch.mock.calls.filter(([url]) => String(url) === '/v1/residents/r1/schedule/free-time').length;
      const before = reads();
      window.dispatchEvent(new Event('focus'));
      await waitFor(() => expect(reads()).toBeGreaterThan(before));
    } finally {
      location.hash = '';
    }
  });
});
