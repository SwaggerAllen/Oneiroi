import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { useShell } from '../state/store';
import { HouseSearchSheet } from './HouseSearchSheet';

// jsdom has no CSS.escape, which react-aria's collections call.
if (typeof globalThis.CSS === 'undefined') (globalThis as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s: string) => s };

describe('the house is searched as a resident is (2026-11-17)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    useShell.getState().setSearchOpen(false);
  });

  it('searches its threads, records and charter by scope, and opens a hit in Records', async () => {
    const search = vi.spyOn(api, 'householdSearch').mockResolvedValue({
      q: 'heron',
      scope: 'threads',
      results: [{ type: 'thread', path: 'threads/2026-11-17-plans', title: 'Plans', at: '2026-11-17T10:00:00Z', snippet: 'The heron walk is Sunday.…' }],
    });
    render(
      <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
        <HouseSearchSheet />
      </QueryClientProvider>,
    );
    act(() => useShell.getState().setSearchOpen(true));
    fireEvent.click(await screen.findByText('Threads'));
    fireEvent.change(screen.getByRole('searchbox', { name: 'Search' }), { target: { value: 'heron' } });
    await waitFor(() => expect(search).toHaveBeenCalledWith('heron', 'threads'));
    const hit = await screen.findByRole('link', { name: /Thread · Plans/ });
    expect(hit.getAttribute('href')).toContain('records/doc/threads/2026-11-17-plans');
  });
});
