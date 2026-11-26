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

  // sunna#109 (the witness, 2026-11-26: a stopped line stalled with nothing to say so).
  it('says her line rests after a stop, links the failed task, and resumes it', async () => {
    const stopped: NeedsYouEntry = {
      kind: 'work_stopped',
      ref: '12.1',
      since: '2026-11-26T18:15:40Z',
      screen: 'queue',
      long: false,
      about: { task: 12, act: '12.1', by: 'safe_word', words: 'Her work line rests: she stopped its run with her safe word' },
    };
    vi.spyOn(api, 'needsYou').mockResolvedValue([stopped]);
    vi.spyOn(api, 'waitingOnHer').mockResolvedValue([]);
    vi.spyOn(api, 'pushConfig').mockRejectedValue(new Error('none'));
    const resume = vi.spyOn(api, 'resumeWork').mockResolvedValue(undefined);
    useShell.setState({ overlay: 'bell' });
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
          <Bell />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );

    expect(await screen.findByText('Her work line rests: she stopped its run with her safe word')).toBeTruthy();
    expect(screen.getByText(/Task #12/).closest('a')?.getAttribute('href')).toBe('#/settings/queue/task/12/act/12.1');
    fireEvent.click(screen.getByRole('button', { name: 'Resume her work line' }));
    await waitFor(() => expect(resume).toHaveBeenCalledWith('r1', 'resumed from the bell'));
  });

  // The witness, 2026-11-26: her succession's parts at the top, each opening its page.
  it('puts succession entries first, opening their succession page', async () => {
    const older: NeedsYouEntry = { kind: 'ask', ref: 3, since: '2026-11-01T09:00:00Z', screen: 'inbox', long: true, about: { subject: 'A tool' } };
    const judge: NeedsYouEntry = {
      kind: 'succession_judge',
      ref: 1,
      since: '2026-11-25T09:00:00Z',
      screen: 'succession',
      long: false,
      about: { page: 'judge', words: '4 to judge', dry_run: true },
    };
    vi.spyOn(api, 'needsYou').mockResolvedValue([older, judge]);
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
    const link = (await screen.findByText('4 to judge')).closest('a') as HTMLAnchorElement;
    expect(link.getAttribute('href')).toBe('#/settings/succession/judge');
    expect(link.textContent).toContain('Succession · runs to judge · DRY RUN');
    // Above the older ask, though the ask has waited longer.
    const ask = screen.getByText('A tool');
    expect(link.compareDocumentPosition(ask) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
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
