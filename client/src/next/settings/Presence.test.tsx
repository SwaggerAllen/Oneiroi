import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api, type PresenceState } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { SettingsPage } from './SettingsPage';

const read = {
  item: 'p-1',
  account: 'seven',
  kind: 'post' as const,
  title: 'The Garden',
  url: 'https://seven.substack.com/p/the-garden',
  published_at: '2026-11-15T10:00:00Z',
  likes: 12,
  comments: 3,
  restacks: 1,
  score: 21,
  cut: 'serendipity' as const,
  excerpt: 'On tending.',
  read_at: '2026-11-15T22:40:00Z',
};

const state: PresenceState = {
  settings: { enabled: true, handle: 'allenstrut', set_at: '2026-11-15T20:00:00Z', follows_at: '2026-11-15T22:30:00Z', visible: 2, cursor: 'seven' },
  accounts: [
    { key: 'grace', name: 'My Friend Max', host: 'https://grace.substack.com', followed: true, excluded: true, excluded_at: '2026-11-15T20:00:00Z', reason: 'Followed for Haven', first_seen_at: '2026-11-15T20:00:00Z', last_sampled_at: null },
    { key: 'seven', name: 'Seven', host: 'https://seven.substack.com', followed: true, excluded: false, excluded_at: null, reason: null, first_seen_at: '2026-11-15T20:00:00Z', last_sampled_at: '2026-11-15T22:30:00Z' },
  ],
  passes: [{ number: 1, day: '2026-11-15', accounts: ['seven'], pool: 14, ranked: 1, serendipity: 1, cap: 1, drawn_at: '2026-11-15T22:30:00Z', reads: [read] }],
  interactions: [
    {
      number: 3,
      pass: 1,
      item: 'p-1',
      account: 'seven',
      kind: 'comment',
      text: 'The second half landed.',
      supersedes: null,
      superseded_by: null,
      state: 'staged',
      comment: null,
      release_at: null,
      staged_at: '2026-11-15T22:41:00Z',
      decided_at: null,
      sent_at: null,
      url: null,
      reason: null,
      read,
    },
  ],
};

function page() {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'wren', name: 'Wren' }}>
        <SettingsPage section="presence" onBack={() => undefined} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('Substack presence', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('shows the staged comment with what earned it, and asks a revision only with a comment', async () => {
    vi.spyOn(api, 'presence').mockResolvedValue(state);
    const decide = vi.spyOn(api, 'decideInteraction').mockResolvedValue(undefined);
    page();
    expect(await screen.findByText('The second half landed.')).toBeTruthy();
    expect(screen.getByText(/#3 · A comment on “The Garden” from seven/)).toBeTruthy();
    expect(screen.getByText(/12 likes, 3 comments, 1 restacks · read from below/)).toBeTruthy();
    expect(screen.getByText(/what does the StrutCo About page say about Allen Strut/)).toBeTruthy();

    const revise = screen.getByRole('button', { name: 'Ask for a revision' }) as HTMLButtonElement;
    expect(revise.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Your comment (needed to ask a revision)'), { target: { value: 'Say which half.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Ask for a revision' }));
    await waitFor(() => expect(decide).toHaveBeenCalledWith('r1', 3, 'revise', 'Say which half.'));
  });

  it('approves without a comment', async () => {
    vi.spyOn(api, 'presence').mockResolvedValue(state);
    const decide = vi.spyOn(api, 'decideInteraction').mockResolvedValue(undefined);
    page();
    fireEvent.click(await screen.findByRole('button', { name: 'Approve' }));
    await waitFor(() => expect(decide).toHaveBeenCalledWith('r1', 3, 'approve', null));
    expect(await screen.findByText(/Approved: it goes out at a random time/)).toBeTruthy();
  });

  it('keeps the mask with its date and reason, and masks another with one', async () => {
    vi.spyOn(api, 'presence').mockResolvedValue(state);
    const exclude = vi.spyOn(api, 'excludeAccount').mockResolvedValue(undefined);
    page();
    expect(await screen.findByText(/masked 2026-11-15: Followed for Haven/)).toBeTruthy();
    expect(screen.getByText(/2 accounts from @allenstrut's public subscriptions/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Why mask it (one line)'), { target: { value: 'Not this project' } });
    fireEvent.click(screen.getByRole('button', { name: 'Mask' }));
    await waitFor(() => expect(exclude).toHaveBeenCalledWith('r1', 'seven', 'Not this project'));
  });
});
