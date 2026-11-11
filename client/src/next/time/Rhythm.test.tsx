import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { ScheduleToday } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { Rhythm } from './Rhythm';

const today: ScheduleToday = {
  day: '2026-11-10',
  now: '2026-11-10T12:00:00Z',
  timezone: 'Etc/UTC',
  checkins: [{ key: 'c1', label: 'Morning', time: '09:00', parts: ['dates'], prompt: null, last_day: null, last_outcome: null, last_at: null }],
  firings: [],
  last: null,
  next: { label: 'Morning', time: '09:00', tomorrow: true },
  free_times: [{ time: '15:00', today: null }],
  free_time_once: [],
  free_time_last: null,
  quiet: null,
  rounds: { every_hours: 4, every_default: true, waking: '08:00-22:00', waking_default: true, waking_from_quiet: false, today: 2, last_at: null },
  dates: [],
  checkin_parts: [{ key: 'dates', label: 'Dates', about: 'what comes up' }],
};

function mount() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'mira', name: 'Mira' }}>
        <Rhythm />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('Rhythm', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('deletes a check-in only on the second press, and never offers to remove free time', async () => {
    vi.spyOn(api, 'schedule').mockResolvedValue(today);
    const del = vi.spyOn(api, 'deleteCheckin').mockResolvedValue(undefined);
    mount();
    fireEvent.click(await screen.findByRole('button', { name: 'Delete' }));
    expect(del).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Delete Morning' }));
    await waitFor(() => expect(del).toHaveBeenCalledWith('r1', 'c1'));
    expect(screen.queryByRole('button', { name: /Remove/ })).toBeNull();
  });

  it('adds a free-time slot to the ones she has', async () => {
    vi.spyOn(api, 'schedule').mockResolvedValue(today);
    const set = vi.spyOn(api, 'setFreeTime').mockResolvedValue(undefined);
    mount();
    fireEvent.change(await screen.findByLabelText('A new daily free-time slot'), { target: { value: '20:30' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add a slot' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('r1', ['15:00', '20:30']));
  });

  it('sets rounds only with a whole number of hours and a window', async () => {
    vi.spyOn(api, 'schedule').mockResolvedValue(today);
    const set = vi.spyOn(api, 'setRounds').mockResolvedValue(undefined);
    mount();
    const every = await screen.findByLabelText('Every (hours, 0 is off)');
    fireEvent.change(every, { target: { value: 'x' } });
    expect((screen.getByRole('button', { name: 'Set rounds' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(every, { target: { value: '6' } });
    fireEvent.click(screen.getByRole('button', { name: 'Set rounds' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('r1', 6, '08:00-22:00'));
  });
});
