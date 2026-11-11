import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { Ledger, WorkItem, WorkQueue } from '../../api/types';
import { SubjectContext } from '../state/resident';
import type { SettingsSection } from '../state/routes';
import { SettingsPage } from './SettingsPage';

const item = (number: number, what: string): WorkItem => ({
  number,
  what,
  done_when: 'it ships',
  status: 'open',
  blocked_on: null,
  position: number,
  added_by: 'resident',
  added_at: '2026-11-01T00:00:00Z',
  note: null,
  moved_by: null,
  moved_at: null,
  shipped: null,
  slipped: null,
  why: null,
  wrapped_at: null,
  runs: 0,
  session_key: null,
});

const queue: WorkQueue = {
  items: [item(1, 'Read the essay'), item(2, 'Write the reply')],
  running: null,
  running_since: null,
  rested: null,
  rested_at: null,
  runs_today: 0,
  runs_a_day: 6,
  budget: null,
  armed: false,
};

function page(section: SettingsSection, onBack = () => undefined) {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
        <SettingsPage section={section} onBack={onBack} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('settings pages', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('arms the work line, reorders, and moves an item only with a note', async () => {
    vi.spyOn(api, 'work').mockResolvedValue(queue);
    const arm = vi.spyOn(api, 'armWork').mockResolvedValue(undefined);
    const order = vi.spyOn(api, 'orderWork').mockResolvedValue(undefined);
    const move = vi.spyOn(api, 'moveWork').mockResolvedValue(undefined);
    const back = vi.fn();
    page('work', back);

    fireEvent.click(await screen.findByRole('button', { name: 'Arm the work line' }));
    await waitFor(() => expect(arm).toHaveBeenCalledWith('r1'));

    fireEvent.click(await screen.findByRole('button', { name: 'Move up' }));
    await waitFor(() => expect(order).toHaveBeenCalledWith('r1', [2, 1]));

    const done = screen.getAllByRole('button', { name: 'Done' })[0];
    expect((done as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('A note on #1'), { target: { value: 'finished it' } });
    fireEvent.click(screen.getAllByRole('button', { name: 'Done' })[0]);
    await waitFor(() => expect(move).toHaveBeenCalledWith('r1', 1, 'done', null, 'finished it'));

    fireEvent.click(screen.getByRole('button', { name: '‹ Back' }));
    expect(back).toHaveBeenCalled();
  });

  it('changes a budget line from the line itself', async () => {
    const ledger: Ledger = {
      key: { present: true, stored_at: '2026-11-01T00:00:00Z' },
      purposes: ['chat', 'work'],
      budgets: [{ purpose: 'work', period: 'week', cap: '3.00', spent: '1.10', exceeded: false }],
      spend: { since: '2026-11-01T00:00:00Z', by_purpose: [], by_model: [], by_actor: [] },
    };
    vi.spyOn(api, 'ledger').mockResolvedValue(ledger);
    const set = vi.spyOn(api, 'setBudget').mockResolvedValue(undefined);
    page('ledger');

    expect(await screen.findByText('$1.10 of $3.00 a week')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Change the work line' }));
    fireEvent.change(screen.getByLabelText('Cap in dollars (blank for no limit)'), { target: { value: '4' } });
    fireEvent.click(screen.getByRole('button', { name: 'Set the line' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('r1', 'work', '4', 'week'));
    expect(await screen.findByText('work: $4 a week.')).toBeTruthy();
  });
});
