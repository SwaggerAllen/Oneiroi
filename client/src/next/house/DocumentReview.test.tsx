import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { DocumentContext, QueueCard } from '../../api/types';
import { DocumentScreen } from './DocumentScreen';

// The witness, 2026-11-27: task #11's review refused "an approval names
// the revision approved, its pin" — the screen never sent one (sunna#110).

const review = {
  act: '11.7',
  task: 11,
  layer: 3,
  name: 'Review the PR',
  type: 'review',
  assignee: 'witness:a1',
  status: 'pending',
  view: 'ready',
  gated: true,
  artifact: 'house/rook:doc/plans/week.md',
  destination: null,
  action: 'merge',
  optional: false,
  throwback: null,
  waits_on: null,
  blocker: null,
  reason: null,
  pin: null,
  approved_pin: null,
  note: null,
  ready_at: null,
  updated_at: '2026-11-27T21:00:00Z',
  task_title: 'Janus',
  project: 'oneiroi',
  owner: 'resident:r1',
} as unknown as QueueCard;

function page(context: Partial<DocumentContext>) {
  vi.spyOn(api, 'documentContext').mockResolvedValue({ citation: 'house/rook:doc/plans/week.md', resident_id: null, mine: null, house: null, tasks: [], review, revision: null, ...context } as DocumentContext);
  vi.spyOn(api, 'queue').mockRejectedValue(new Error('no queue'));
  vi.spyOn(api, 'householdRead').mockResolvedValue({ path: 'plans/week.md', title: 'Week', content: 'Plans.' } as never);
  const move = vi.spyOn(api, 'queueMove').mockResolvedValue({ ok: true });
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queries}>
      <DocumentScreen citation="house/rook:doc/plans/week.md" onBack={() => undefined} />
    </QueryClientProvider>,
  );
  return move;
}

describe('a review approved from the document screen (sunna#110)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('names the revision it shows as its pin', async () => {
    const move = page({ revision: '0123456789abcdef' });
    fireEvent.click(await screen.findByRole('button', { name: 'Review' }));
    expect(screen.getByText(/Reviewing the revision at 0123456/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Your note'), { target: { value: 'Looks right.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Approve' }));
    await waitFor(() => expect(move).toHaveBeenCalledWith(11, '11.7', 'decide', { outcome: 'approved', note: 'Looks right.', pin: '0123456789abcdef' }));
  });

  it('offers no approval when it cannot say which revision it shows', async () => {
    page({ revision: null });
    fireEvent.click(await screen.findByRole('button', { name: 'Review' }));
    fireEvent.change(screen.getByLabelText('Your note'), { target: { value: 'Hm.' } });
    expect((screen.getByRole('button', { name: 'Approve' }) as HTMLButtonElement).disabled).toBe(true);
    expect((screen.getByRole('button', { name: 'Ask for changes' }) as HTMLButtonElement).disabled).toBe(false);
  });
});
