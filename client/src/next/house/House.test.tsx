import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, type HouseBeats, type HouseContract, type HouseShelf } from '../../api/client';
import { HOUSE_SUBJECT, SubjectContext } from '../state/resident';
import { Charter } from './Charter';
import { TabBar } from '../shell/TabBar';
import { HouseRecords } from './HouseRecords';
import { HouseTime } from './HouseTime';
import { Threads } from './Threads';

const shelf: HouseShelf = {
  household_id: 'h1',
  slug: null,
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
  catalog: [
    { key: 'witnesses_post', label: 'Witnesses post', about: 'Whether witnesses may post at all.', default: true, type: 'boolean' },
    { key: 'witness_posts', label: 'How often witnesses post', about: 'per_beat, queue_emptied or unbounded.', default: 'per_beat', type: 'choice', options: ['per_beat', 'queue_emptied', 'unbounded'] },
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

  it('lists threads as the chat does, opens one in place, and the composer replies in it', async () => {
    vi.spyOn(api, 'householdRead').mockResolvedValue({
      path: 'threads/checkin-2026-11-16-morning',
      kind: 'thread',
      title: 'Morning, 2026-11-16',
      content: '',
      trunk: { path: 't', meta: { by: 'the platform', posted_at: '2026-11-16T15:30:00Z' }, body: 'The house checks in: Morning.' },
      replies: [{ path: 'r', meta: { reply: '1', by: 'Lily', by_kind: 'resident', by_id: 'r1', at: '2026-11-16T15:40:00Z' }, body: 'The writing moved.' }],
      ballot: null,
    });
    const reply = vi.spyOn(api, 'householdReply').mockResolvedValue({ number: 2 });
    mount(<Threads />);
    // No thread open: a title and words start one.
    expect(await screen.findByPlaceholderText("A new thread's title")).toBeTruthy();
    fireEvent.click(await screen.findByRole('button', { name: /Morning, 2026-11-16/ }));
    expect(await screen.findByText('The writing moved.')).toBeTruthy();
    // One open: the title field is gone, and the words reply in it.
    expect(screen.queryByPlaceholderText("A new thread's title")).toBeNull();
    fireEvent.change(screen.getByPlaceholderText('Reply in “Morning, 2026-11-16”'), { target: { value: 'Good work.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Reply' }));
    await waitFor(() => expect(reply).toHaveBeenCalledWith('threads/checkin-2026-11-16-morning', 'Good work.'));
  });

  it('posts a new thread from the composer', async () => {
    const post = vi.spyOn(api, 'householdPost').mockResolvedValue({ path: 'threads/plans' });
    vi.spyOn(api, 'householdRead').mockResolvedValue({ path: 'threads/plans', title: 'Plans', content: 'x' });
    mount(<Threads />);
    fireEvent.change(await screen.findByPlaceholderText("A new thread's title"), { target: { value: 'Plans' } });
    fireEvent.change(screen.getByPlaceholderText('Its first words, for the whole house'), { target: { value: 'For the week.' } });
    fireEvent.click(screen.getByRole('button', { name: 'Post the thread' }));
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

  it('names the house once for citations, and then shows how its threads are cited', async () => {
    const name = vi.spyOn(api, 'nameHousehold').mockResolvedValue({ ...shelf, slug: 'rookery' });
    mount(<Charter />);
    const card = await screen.findByRole('region', { name: "The house's name" });
    const field = within(card).getByLabelText('Name (lowercase letters, digits and hyphens)');
    fireEvent.change(field, { target: { value: 'Rook House' } });
    expect((within(card).getByRole('button', { name: 'Name the house' }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.change(field, { target: { value: 'rookery' } });
    fireEvent.click(within(card).getByRole('button', { name: 'Name the house' }));
    await waitFor(() => expect(name).toHaveBeenCalledWith('rookery'));
  });

  it('a named house says how its threads are cited, with nothing to change', async () => {
    vi.spyOn(api, 'householdShelf').mockResolvedValue({ ...shelf, slug: 'rookery' });
    mount(<Charter />);
    const card = await screen.findByRole('region', { name: "The house's name" });
    expect(within(card).getByText('house/rookery:thread/…')).toBeTruthy();
    expect(within(card).queryByRole('button', { name: 'Name the house' })).toBeNull();
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

  it('founds the charter with its own settings, not only its prose (gaia#50)', async () => {
    vi.spyOn(api, 'householdContract').mockResolvedValue({ ...contract, in_force: null, versions: [], ballots: [] });
    const found = vi.spyOn(api, 'householdProposeCharter').mockResolvedValue(contract);
    mount(<Charter />);
    expect(await screen.findByText('Found the charter')).toBeTruthy();
    fireEvent.change(screen.getByLabelText('The charter'), { target: { value: 'We share this house.' } });
    fireEvent.click(screen.getByRole('button', { name: '+ A setting' }));
    fireEvent.change(screen.getByLabelText('Setting 1'), { target: { value: 'witness_posts' } });
    fireEvent.change(screen.getByLabelText('Value'), { target: { value: 'unbounded' } });
    fireEvent.change(screen.getByLabelText('A note for the record'), { target: { value: 'founding' } });
    fireEvent.click(screen.getByRole('button', { name: 'Propose version 1' }));
    await waitFor(() => expect(found).toHaveBeenCalledWith('We share this house.', 'founding', [{ setting: 'witness_posts', value: 'unbounded' }]));
  });

  it('lists every setting, and Propose a change opens the ballot with it filled in (gaia#49)', async () => {
    const post = vi.spyOn(api, 'householdPost').mockResolvedValue({ path: 'threads/witness-posts' });
    mount(<Charter />);
    const settings = await screen.findByRole('list', { name: 'Settings' });
    expect(within(settings).getAllByText(/per_beat/).length).toBeGreaterThan(0);
    const row = within(settings).getByText('How often witnesses post').closest('li') as HTMLElement;
    fireEvent.click(within(row).getByRole('button', { name: 'Propose a change' }));
    const form = screen.getByRole('form', { name: 'Propose a change' });
    expect((within(form).getByLabelText('Title') as HTMLInputElement).value).toBe('Change: How often witnesses post');
    fireEvent.change(within(form).getByLabelText('Value'), { target: { value: 'unbounded' } });
    fireEvent.change(within(form).getByLabelText('A note for the record'), { target: { value: 'we are three' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Open the ballot' }));
    await waitFor(() =>
      expect(post).toHaveBeenCalledWith({
        title: 'Change: How often witnesses post',
        content: '',
        ballot: { bundle: [{ setting: 'witness_posts', value: 'unbounded' }], term_days: 7, note: 'we are three' },
      }),
    );
  });

  it('keeps time as Rhythm does: the turn open, check-ins, and the zone from a list', async () => {
    const set = vi.spyOn(api, 'setHouseCheckin').mockResolvedValue({ zone: 'America/Los_Angeles', checkins: [] });
    const clock = vi.spyOn(api, 'setHouseClock').mockResolvedValue({ zone: 'Europe/London', checkins: [] });
    mount(<HouseTime />);
    expect(await screen.findByText(/Lily holds the turn/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Label'), { target: { value: 'Evening wrap' } });
    fireEvent.change(screen.getByLabelText('Time', { selector: 'input' }), { target: { value: '21:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add a check-in' }));
    await waitFor(() => expect(set).toHaveBeenCalledWith('evening-wrap', 'Evening wrap', '21:00'));
    const zone = screen.getByRole('combobox', { name: 'Zone' }) as HTMLSelectElement;
    expect(zone.value).toBe('America/Los_Angeles');
    fireEvent.change(zone, { target: { value: 'Europe/London' } });
    fireEvent.click(screen.getByRole('button', { name: 'Set the zone' }));
    await waitFor(() => expect(clock).toHaveBeenCalledWith('Europe/London'));
  });

  it('under round-robin threads, shows the turns open and how the last went, not the beat', async () => {
    vi.spyOn(api, 'householdBeats').mockResolvedValue({
      ...beats,
      conversation: 'round_robin',
      rounds: [
        { turn_id: '2', thread: 'threads/herons', round: 1, resident_id: 'r1', name: 'Lily', issued_at: '2026-11-16T16:00:00Z', expires_at: '2026-11-16T16:10:00Z', outcome: null, spent_at: null },
        { turn_id: '1', thread: 'threads/herons', round: 1, resident_id: 'r2', name: 'Scarlett', issued_at: '2026-11-16T15:50:00Z', expires_at: '2026-11-16T16:00:00Z', outcome: 'skipped', spent_at: '2026-11-16T15:52:00Z' },
      ],
    });
    mount(<HouseTime />);
    expect(await screen.findByText(/Lily · threads\/herons, round 1/)).toBeTruthy();
    expect(screen.getByText('skipped')).toBeTruthy();
    expect(screen.queryByText(/holds the turn/)).toBeNull();
  });

  it("records: the house's repository in the residents' tree", async () => {
    vi.spyOn(api, 'householdFiles').mockResolvedValue({
      kinds: [
        { kind: 'house', label: 'The house', position: 0 },
        { kind: 'thread', label: 'Threads', position: 1 },
      ],
      documents: [
        { kind: 'house', path: 'CONTRACT.md', title: 'The household contract', status: null, bytes: null, versions: 1, written_at: null, written_by: null, missing_at: null, note: null },
        { kind: 'thread', path: 'threads/plans', title: 'Plans', status: null, bytes: null, versions: 2, written_at: '2026-11-16T10:00:00Z', written_by: 'Lily', missing_at: null, note: null },
      ],
      unadopted: [],
    });
    vi.stubGlobal('matchMedia', (q: string) => ({ matches: false, media: q, addEventListener: () => undefined, removeEventListener: () => undefined }));
    mount(<HouseRecords path="" />);
    expect((await screen.findAllByRole('button', { name: /The house/ })).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('button', { name: /Threads/ }).length).toBeGreaterThan(0);
    expect(screen.queryByRole('button', { name: /folder settings/ })).toBeNull();
    vi.unstubAllGlobals();
  });
});
