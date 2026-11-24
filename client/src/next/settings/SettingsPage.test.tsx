import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { Ledger, WorkQueue } from '../../api/types';
import { SubjectContext } from '../state/resident';
import type { SettingsSection } from '../state/routes';
import { SettingsPage } from './SettingsPage';

const queue: WorkQueue = {
  running_since: null,
  running_act: null,
  running_task: null,
  rested: null,
  rested_at: null,
  runs_today: 3,
  runs_a_day: 1000,
  activity_runs: [{ act: '12.1', runs: 20 }],
  runs_an_activity: 20,
  budget: null,
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

  // sunna#101, #102: the line, its runs and the give-back; the old items are retired.
  it('shows the line and gives the runs back only with a note', async () => {
    vi.spyOn(api, 'work').mockResolvedValue({ ...queue, running_act: '12.1', running_task: 12, running_since: new Date().toISOString() });
    const reset = vi.spyOn(api, 'resetWorkRuns').mockResolvedValue(undefined);
    const back = vi.fn();
    page('work', back);

    expect(await screen.findByText(/Running activity 12\.1 of task #12/)).toBeTruthy();
    expect(screen.getByRole('link', { name: 'Open task #12 ›' }).getAttribute('href')).toBe('#/settings/queue/task/12');
    expect(screen.getByText(/12\.1 20 of 20/)).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Arm the work line' })).toBeNull();

    const give = screen.getByRole('button', { name: 'Give the runs back' }) as HTMLButtonElement;
    expect(give.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Why the runs come back (she reads it)'), { target: { value: 'go again' } });
    fireEvent.click(give);
    await waitFor(() => expect(reset).toHaveBeenCalledWith('r1', 'go again'));

    fireEvent.click(screen.getByRole('button', { name: '‹ Back' }));
    expect(back).toHaveBeenCalled();
  });

  // sunna#76: a line waiting on her free time can go ahead, by his hand, with a note.
  it('lets you start work ahead of a free-time pass the line is waiting on', async () => {
    vi.spyOn(api, 'work').mockResolvedValue({ ...queue, rested: 'waiting: a free-time pass is underway, and care comes first; work resumes when it closes' });
    const skip = vi.spyOn(api, 'skipWorkCare').mockResolvedValue(undefined);
    page('work');
    fireEvent.change(await screen.findByLabelText('Why work goes ahead (she reads it)'), { target: { value: 'the doc is due' } });
    fireEvent.click(screen.getByRole('button', { name: 'Start work now' }));
    await waitFor(() => expect(skip).toHaveBeenCalledWith('r1', 'the doc is due'));
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
