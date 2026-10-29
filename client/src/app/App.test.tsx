import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App } from './App';

// The shell against a faked fetch: a stranger sees the sign-in, a
// steward with no resident sees the empty state. No network (conventions §9).
function fakeFetch(routes: Record<string, { status: number; body?: unknown }>) {
  return vi.fn(async (input: RequestInfo | URL) => {
    const path = typeof input === 'string' ? input : input instanceof URL ? input.pathname : input.url;
    const route = routes[path] ?? { status: 404, body: { error: { kind: 'not_found', meaning: 'no route' } } };
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

  it('shows the empty state for a steward with no resident', async () => {
    vi.stubGlobal(
      'fetch',
      fakeFetch({ '/v1/me': { status: 200, body: { email: 'a@b', residents: [] } }, '/v1/residents': { status: 200, body: [] } }),
    );
    render(<App />);
    await waitFor(() => expect(screen.getByText(/No resident yet/)).toBeTruthy());
  });
});
