import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, type HouseBeats, type HouseContract, type HouseShelf } from '../../api/client';
import { HOUSE_SUBJECT, SubjectContext } from '../state/resident';
import { Charter } from './Charter';
import { TabBar } from '../shell/TabBar';
import { HouseTime } from './HouseTime';
import { Threads } from './Threads';

const shelf: HouseShelf = {
  household_id: 'h1',
  contract: 'CONTRACT.md',
  total: 1,
  from: 0,
  next: null,
  threads: [
    {
      kind: 'thread',
      path: 'threads/checkin-2026-11-16-morning',
      title: 'Morning, 2026-11-16',
      by: 'the platform',
      posted_at: '2026-11-16T15:30:00Z',
      replies: 1,
      last_reply_at: '2026-11-16T15:40:00Z',
      ballot: null,
    },
  ],
  documents: [],
};

const contract: HouseContract = {
  household_id: 'h1',
  in_force: { version: 1, prose: 'We share this house.', rules: [], settings: {}, bundle: null, ballot: null, decided_by: null, decided_at: '2026-11-11T10:00:00Z', note: 'founding' },
  versions: [],
  members: [
    { kind: 'witness', id: 'a1', name: "Lily's witness", joined_at: '2026-11-11T10:00:00Z', signed_version: 1 },
    { kind: 'resident', id: 'r1', name: 'Lily', joined_at: '2026-11-11T10:00:00Z', signed_version: 1 },
  ],
  ballots: [
    {
      number: 2,
      thread: 'threads/quiet-mornings',
      bundle: [{ rule: 'No posts before 07:00.' }],
      term_days: 7,
      opened_by: 'Lily',
      opened_at: '2026-11-15T10:00:00Z',
      closes_at: '2026-11-22T10:00:00Z',
      note: 'mornings are for the work',
      closed_at: null,
      passed: null,
      yes: 1,
      no: 0,
      members: 3,
    },
  ],
};

const beats: HouseBeats = {
  shape: { beat: 60, quota: 6 },
  now: '2026-11-16T16:10:00Z',
  beat: { top: '2026-11-16T16:00:00Z', signup_closes: '2026-11-16T16:05:00Z', ends: '2026-11-16T17:00:00Z', turns_fired: 1, turns: [] },
  next_top: '2026-11-16T17:00:00Z',
  open_turn: { turn: 4, resident_id: 'r1', name: 'Lily', beat_top: '2026-11-16T16:00:00Z', fired_at: '2026-11-16T16:06:00Z', ends_by: '2026-11-16T16:16:00Z', ended_at: null, outcome: null },
  queue: [],
  upcoming: [],
  profiles: [{ kind: 'resident', id: 'r1', name: 'Lily', profile: 'on_turn', missed: 0 }],
  closed: [],
  you: { kind: 'witness', profile: 'self', quota: 6, quota_left: 5, quota_window_hours: 24 },
};

function mount(node: React.ReactNode) {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: HOUSE_SUBJECT, slug: HOUSE_SUBJECT, name: 'The house', kind: 'house' }}>{node}</SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

describe('the house as a subject (2026-11-16)', () => {
  beforeEach(() => {
    vi.spyOn(api, 'householdShelf').mockResolvedValue(shelf);
    vi.spyOn(api, 'householdContract').mockResolvedValue(contract);
    vi.spyOn(api, 'householdBeats').mockResolvedValue(beats);
    vi.spyOn(api, 'houseCheckins').mockResolvedValue({ zone: 'America/Los_Angeles', checkins: [] });
    vi.spyOn(api, 'me').mockResolvedValue({ account_id: 'a1', email: 'w@example.com', residents: ['r1'] });
  });
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("has a resident's tabs, its soul its charter", () => {
    mount(<TabBar active="chat" onSelect={() => undefined} house />);
    const tabs = screen.getByRole('navigation', { name: 'Sections' });
    expect(within(tabs).getByRole('button', { name: /Charter/ })).toBeTruthy();
    expect(within(tabs).queryByRole('button', { name: /Soul/ })).toBeNull();
    expect(within(tabs).getByRole('button', { name: /Chat/ })).toBeTruthy();
  });

  it('lists the threads, opens one whole, and replies', async () => {
    vi.spyOn(api, 'householdRead').mockResolvedValue({
      path: 'threads/checkin-2026-11-16-morning',
      kind: 'thread',
      title: 'Morning, 2026-11-16',
      content: '',
      trunk: { path: 't', meta: { by: 'the platform', posted_at: '2026-11-16T15:30:00Z' }, body: 'The house checks in: Morning.' },
      replies: [{ path: 'r', meta: { reply: '1', by: 'Lily', at: '2026-11-16T15:40:00Z' }, body: 'The writing moved.' }],
      ballot: null,
    });
    const reply = vi.spyOn(api, 'householdReply').mockResolvedValue({ number: 2 });
    mount(<Threads />);
    fireEvent.click(await screen.findByRole('button', { name: 'Morning, 2026-11-16' }));
    expect(await screen.findByText('The writing moved.')).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Reply'), { target: { value: 'Good work.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Reply' }));
    await waitFor(() => expect(reply).toHaveBeenCalledWith('threads/checkin-2026-11-16-morning', 'Good work.'));
  });

  it('posts a new thread', async () => {
    const post = vi.spyOn(api, 'householdPost').mockResolvedValue({ path: 'threads/plans' });
    vi.spyOn(api, 'householdRead').mockResolvedValue({ path: 'threads/plans', title: 'Plans', content: 'x' });
    mount(<Threads />);
    fireEvent.change(screen.getByLabelText('Title'), { target: { value: 'Plans' } });
    fireEvent.change(screen.getByLabelText('Your words'), { target: { value: 'For the week.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Post' }));
    await waitFor(() => expect(post).toHaveBeenCalledWith({ title: 'Plans', content: 'For the week.' }));
  });

  it('shows the charter in force, its members, and votes on an open ballot', async () => {
    const vote = vi.spyOn(api, 'householdVote').mockResolvedValue({ number: 3 });
    mount(<Charter />);
    expect(await screen.findByText('We share this house.')).toBeTruthy();
    expect(screen.getByText('Rule: No posts before 07:00.')).toBeTruthy();
    const ballot = screen.getByRole('article', { name: 'Ballot #2' });
    fireEvent.click(within(ballot).getByRole('button', { name: 'Yes' }));
    await waitFor(() => expect(vote).toHaveBeenCalledWith('threads/quiet-mornings', 'yes', ''));
  });

  it('proposes a change as a ballot', async () => {
    const post = vi.spyOn(api, 'householdPost').mockResolvedValue({ path: 'threads/witnesses' });
    mount(<Charter />);
    const form = await screen.findByRole('form', { name: 'Propose a change' });
    fireEvent.change(within(form).getByLabelText('Title'), { target: { value: 'Witnesses' } });
    fireEvent.click(within(form).getByRole('button', { name: '+ A setting' }));
    fireEvent.change(within(form).getByLabelText('Rule 1'), { target: { value: 'Be kind.' } });
    fireEvent.change(within(form).getByLabelText('Setting 2'), { target: { value: 'witnesses_post' } });
    fireEvent.change(within(form).getByLabelText('Value'), { target: { value: 'false' } });
    fireEvent.change(within(form).getByLabelText('A note for the record'), { target: { value: 'the house asked' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Open the ballot' }));
    await waitFor(() =>
      expect(post).toHaveBeenCalledWith({
        title: 'Witnesses',
        content: '',
        ballot: { bundle: [{ rule: 'Be kind.' }, { setting: 'witnesses_post', value: false }], term_days: 7, note: 'the house asked' },
      }),
    );
  });

  it('keeps time: the turn open, the clock and its check-ins', async () => {
    const set = vi.spyOn(api, 'setHouseCheckin').mockResolvedValue({ zone: 'America/Los_Angeles', checkins: [] });
    mount(<HouseTime />);
    expect(await screen.findByText(/Lily holds the turn/)).toBeTruthy();
    fireEvent.change(await screen.findByLabelText('Label'), { target: { value: 'Evening wrap' } });
    fireEvent.change(screen.getByLabelText('Time', { selector: 'input' }), { target: { value: '21:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('evening-wrap', 'Evening wrap', '21:00'));
  });
});
