import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { NeedsYouEntry } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { useShell } from '../state/store';
import { Bell } from './Overlays';

const held: NeedsYouEntry = {
  kind: 'work_held',
  ref: 25,
  since: '2026-11-11T09:00:00Z',
  screen: 'work',
  long: false,
  about: { what: 'The wake wording', ask: 'your word on two wordings', held_by: 'resident', subject: 'Work item #25 held: your word on two wordings' },
};

describe('the bell', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    useShell.setState({ overlay: null });
  });

  it('shows work held for you with its ask, opening the Work page (brain#86)', async () => {
    vi.spyOn(api, 'needsYou').mockResolvedValue([held]);
    vi.spyOn(api, 'waitingOnHer').mockResolvedValue([]);
    vi.spyOn(api, 'pushConfig').mockRejectedValue(new Error('none'));
    useShell.setState({ overlay: 'bell' });
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
          <Bell />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );

    const link = (await screen.findByText('Work item #25 held: your word on two wordings')).closest('a');
    expect(link?.getAttribute('href')).toBe('#/settings/work');
    expect(link?.textContent).toContain('Work · waiting on you');
    expect(await screen.findByText('WAITING ON YOU · 1')).toBeTruthy();
  });
});
