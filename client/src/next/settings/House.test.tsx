import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { SubjectContext } from '../state/resident';
import { SettingsPage } from './SettingsPage';

function page() {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'lily', name: 'Lily' }}>
        <SettingsPage section="house" onBack={() => undefined} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('the house (2026-11-16)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('adds a check-in on the house clock, and replies to the latest thread', async () => {
    vi.spyOn(api, 'houseCheckins').mockResolvedValue({
      zone: 'America/Los_Angeles',
      checkins: [
        {
          key: 'morning',
          label: 'Morning',
          time: '07:30',
          last_day: '2026-11-16',
          last_thread: 'threads/checkin-2026-11-16-morning',
          last_fired_at: '2026-11-16T15:30:00Z',
        },
      ],
    });
    vi.spyOn(api, 'householdRead').mockResolvedValue({ path: 'threads/checkin-2026-11-16-morning', title: 'Morning, 2026-11-16', content: 'Reply #1 by Lily: the writing moved.' });
    const set = vi.spyOn(api, 'setHouseCheckin').mockResolvedValue({ zone: 'America/Los_Angeles', checkins: [] });
    const reply = vi.spyOn(api, 'householdReply').mockResolvedValue({ number: 3 });
    page();

    expect(await screen.findByText(/Reply #1 by Lily: the writing moved\./)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Label'), { target: { value: 'Evening wrap' } });
    fireEvent.change(screen.getByLabelText('Time'), { target: { value: '21:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('evening-wrap', 'Evening wrap', '21:00'));

    fireEvent.change(screen.getByLabelText('Your reply (wakes every resident)'), { target: { value: 'Good work.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Reply to the house' }));
    await waitFor(() => expect(reply).toHaveBeenCalledWith('threads/checkin-2026-11-16-morning', 'Good work.'));
  });
});
