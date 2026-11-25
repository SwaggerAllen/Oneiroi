import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { NeedsYouEntry } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { useShell } from '../state/store';
import { Bell, SubjectSheet } from './Overlays';

describe('the bell', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    useShell.setState({ overlay: null });
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

  // gaia#58 (the witness, 2026-11-19): an unread count by every workspace.
  it('shows each workspace with its unread count', async () => {
    vi.spyOn(api, 'residents').mockResolvedValue([{ id: 'r1', name: 'Mira', slug: 'mira' }] as never);
    vi.spyOn(api, 'me').mockResolvedValue({ account_id: 'a1', email: 'w@example.com', residents: ['r1'] } as never);
    vi.spyOn(api, 'unread').mockResolvedValue({ residents: [{ id: 'r1', count: 3 }], house: { count: 2, threads: {} } });
    useShell.setState({ overlay: 'subject' });
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
          <SubjectSheet />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );
    expect(await screen.findByText(/3 unread/)).toBeTruthy();
    expect(await screen.findByText(/2 unread/)).toBeTruthy();

    // Mark read beside each (the witness, 2026-11-20): the house as a whole, a resident's chat by id.
    const marked = vi.spyOn(api, 'markRead').mockResolvedValue(undefined);
    fireEvent.click(screen.getByRole('button', { name: 'Mark the house read' }));
    await waitFor(() => expect(marked).toHaveBeenCalledWith('house', expect.any(String)));
    fireEvent.click(screen.getByRole('button', { name: 'Mark Mira read' }));
    await waitFor(() => expect(marked).toHaveBeenCalledWith('r1', expect.any(String)));
  });
});
