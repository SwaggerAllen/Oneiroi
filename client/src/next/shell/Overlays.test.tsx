import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
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

  // The witness, 2026-11-18: no way to accept a plugin proposal from the bell.
  it('answers a plugin proposal in place: agree with a note', async () => {
    const proposal: NeedsYouEntry = {
      kind: 'plugin_proposal',
      ref: 1,
      since: '2026-11-18T19:00:00Z',
      screen: 'agreement',
      long: false,
      about: { key: 'honcho', change: 'off', note: 'Retired.' },
    };
    vi.spyOn(api, 'needsYou').mockResolvedValue([proposal]);
    vi.spyOn(api, 'waitingOnHer').mockResolvedValue([]);
    vi.spyOn(api, 'pushConfig').mockRejectedValue(new Error('none'));
    vi.spyOn(api, 'plugins').mockResolvedValue({
      plugins: [],
      proposals: [{ number: 1, key: 'honcho', change: 'off', proposed_by: 'resident', note: 'Retired.', proposed_at: '2026-11-18T19:00:00Z', agreed: null, answer_note: null, answered_at: null }],
    });
    const answer = vi.spyOn(api, 'answerPlugin').mockResolvedValue(undefined);
    useShell.setState({ overlay: 'bell' });
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
          <Bell />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );

    fireEvent.click(await screen.findByText('off honcho'));
    fireEvent.change(await screen.findByLabelText('Your note to Mira'), { target: { value: 'Agreed, cut it.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Agree' }));
    await waitFor(() => expect(answer).toHaveBeenCalledWith('r1', 1, true, 'Agreed, cut it.'));
  });
});
