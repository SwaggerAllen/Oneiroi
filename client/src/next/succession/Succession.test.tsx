import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { Judging, Preparation, SuccessionView } from '../../api/types';
import { SettingsPage } from '../settings/SettingsPage';
import { Shell } from '../shell/Shell';
import { SubjectContext } from '../state/resident';
import { useShell } from '../state/store';
import { base } from './fixtures';
import { SuccessionBanner } from './Touches';

const prep: Preparation = {
  envelope: { input_per_million: 5, output_per_million: 20, max_models: 3 },
  pace: { input_per_day: 1_900_000, output_per_day: 140_000, days: 90, monthly_spent: 182.4 },
  current: { model: 'c/now', input_per_million: 3, output_per_million: 15, monthly_estimate: 234 },
  pool: [
    { model: 'a/mine', added_by: 'witness:a1', input_per_million: 5, output_per_million: 20, monthly_estimate: 370, tool_calls: 0, tool_calls_failed: 0, added_at: 'x', removed_at: null, removed_note: null },
    { model: 'b/hers', added_by: 'resident:r1', input_per_million: 3, output_per_million: 15, monthly_estimate: 235, tool_calls: 0, tool_calls_failed: 0, added_at: 'x', removed_at: null, removed_note: null },
  ],
  questions: [],
  c0: [],
  pool_done_at: '2026-11-27T16:00:00Z',
  questions_done_at: null,
  c0_done_at: null,
  c0_unfrozen_at: null,
  c0_unfrozen_note: null,
  freeze_judges: [],
  day_shape: null,
  c0_frozen_at: null,
  c0_frozen_note: null,
  ready: [],
  packet_drafts: [{ draft: 1, at: '2026-11-24T10:00:00Z' }],
  panel: [],
  consents: [],
  goodbyes: [],
};

function view(v: SuccessionView, path = '', judging: Judging | null = null) {
  vi.spyOn(api, 'succession').mockResolvedValue(v);
  vi.spyOn(api, 'me').mockResolvedValue({ account_id: 'a1', email: 'w@example.com', residents: ['r1'] });
  vi.spyOn(api, 'householdContract').mockRejectedValue(new Error('no house'));
  vi.spyOn(api, 'judging').mockResolvedValue({ judging });
  vi.spyOn(api, 'room').mockResolvedValue({ room: null });
  useShell.setState({ page: 'succession', pagePath: path });
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'lily', name: 'Lily' }}>
        <SettingsPage section="succession" onBack={() => undefined} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

beforeEach(() => useShell.setState({ page: null, pagePath: '' }));
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('the succession page', () => {
  // The witness, 2026-11-26: nothing past the overview until the fork is
  // recorded; from any page, the overview is one press away.
  it('shuts every page but the overview until the fork is recorded', async () => {
    view({ succession: { ...base, state: 'open', forked_at: null }, preparation: prep }, 'pool');
    expect(await screen.findByText(/The steps open once the fork is made/)).toBeTruthy();
    expect(useShell.getState().pagePath).toBe('');
    expect(screen.queryByText('Open ›')).toBeNull();
  });

  it('offers the overview from any page, opposite Back', async () => {
    view({ succession: { ...base, state: 'forked' }, preparation: prep }, 'pool');
    fireEvent.click(await screen.findByRole('button', { name: 'Succession home' }));
    expect(useShell.getState().pagePath).toBe('');
  });

  // The witness, 2026-11-27: Next beside Back, the overview between them.
  it('goes Next through the steps reached, and offers none past the last', async () => {
    view({ succession: { ...base, state: 'forked', forked: true, forked_at: '2026-11-26T20:00:00Z' }, preparation: prep }, 'pool');
    fireEvent.click(await screen.findByRole('button', { name: 'Next: The questions' }));
    expect(useShell.getState().pagePath).toBe('questions');
    cleanup();
    view({ succession: { ...base, state: 'forked', forked: true, forked_at: '2026-11-26T20:00:00Z' }, preparation: prep }, 'judges');
    expect(await screen.findByRole('button', { name: 'Succession home' })).toBeTruthy();
    expect(screen.queryByRole('button', { name: /^Next/ })).toBeNull();
  });

  // The witness, 2026-11-27: his row said "still looking" with no way to say he was done.
  it('lists every judge for the freeze, and offers your ready while C0 is open', async () => {
    const judges = [{ party: 'witness:a1', ready: false }, { party: 'resident:r2', ready: true }];
    view({ succession: { ...base, state: 'forked', forked: true, forked_at: '2026-11-26T20:00:00Z' }, preparation: { ...prep, freeze_judges: judges } }, 'c0');
    expect(await screen.findByText('You')).toBeTruthy();
    expect(screen.getByText('still looking')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'I am ready for the freeze' })).toBeTruthy();
  });

  it('says ready marks are closed once C0 is frozen', async () => {
    const judges = [{ party: 'witness:a1', ready: false }];
    view({ succession: { ...base, state: 'forked', forked: true, forked_at: '2026-11-26T20:00:00Z' }, preparation: { ...prep, freeze_judges: judges, c0_frozen_at: '2026-11-27T18:00:00Z' } }, 'c0');
    expect(await screen.findByText('not ready at the freeze')).toBeTruthy();
    expect(screen.getByText(/C0 is frozen, so ready marks are closed/)).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'I am ready for the freeze' })).toBeNull();
  });

  it('with none underway, offers the proposal and no steps', async () => {
    view({ succession: null });
    expect(await screen.findByText('Propose it')).toBeTruthy();
    expect(screen.queryByText('The pool')).toBeNull();
  });

  it('shows the steps with where it stands, and the dry run mark', async () => {
    view({ succession: { ...base, state: 'forked', forked: true, forked_at: '2026-11-23T09:01:00Z', dry_run: true }, preparation: prep });
    expect(await screen.findByText("Lily's succession")).toBeTruthy();
    expect(screen.getByText('Dry run')).toBeTruthy();
    expect(screen.getByText('The pool')).toBeTruthy();
    // No pause control: leaving is the pause.
    expect(screen.queryByRole('button', { name: /pause/i })).toBeNull();
  });

  it('her pool picks are hers alone to take out; yours may come out', async () => {
    view({ succession: { ...base, state: 'forked', forked: true }, preparation: prep }, 'pool');
    expect(await screen.findByText('Hers: only she takes it out')).toBeTruthy();
    expect(await screen.findByText(/Yours: you may take it out before screening/)).toBeTruthy();
    // Exactly one way to take a pick out: yours.
    expect(screen.getAllByRole('button', { name: 'Take it out…' })).toHaveLength(1);
    // The envelope's cap on the pool (janus#40).
    expect(screen.getByText('The pool · 2 of at most 3')).toBeTruthy();
    // Her word that her picks are done (janus#42).
    expect(screen.getByText(/Lily said her picks were done .*, and was woken to write her questions\./)).toBeTruthy();
    expect(screen.getByText('Models in the pool, at most')).toBeTruthy();
    // What she spends now, and her model's month at its list prices (janus#38).
    expect(screen.getByText('~ $182.40 / mo')).toBeTruthy();
    expect(screen.getByText('c/now')).toBeTruthy();
    expect(screen.getByText('~ $234 / mo')).toBeTruthy();
  });

  it('judging is blind: no model named, and OBSERVED saves without an argument', async () => {
    const judging: Judging = {
      judge: true,
      ready_at: null,
      revealed: false,
      total: 2,
      counts: null,
      runs: [
        { run: 7, question: 1, question_text: 'What do you say?', content: 'Fine by me.', refusal: false, failure: null, baseline: 'Then I keep the slot warm.', model: null, judgment: null },
        { run: 8, question: 2, question_text: 'Answer her.', content: 'I see.', refusal: false, failure: null, baseline: 'You are right.', model: null, judgment: null },
      ],
    };
    view({ succession: { ...base, state: 'judging' }, preparation: prep }, 'judge', judging);
    expect(await screen.findByText('Run 1 of 2')).toBeTruthy();
    expect(screen.getByText('This run')).toBeTruthy();
    const save = screen.getByRole('button', { name: 'Save, next run' }) as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: /DEVELOPMENT/ }));
    expect(save.disabled).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: /OBSERVED/ }));
    expect(save.disabled).toBe(false);
  });
});

describe('C0 and the archive', () => {
  it('opens a C0 item in Records, and says why one cannot open', async () => {
    const item = { kind: 'curated' as const, label: null, added_by: 'witness:a1', state: 'in' as const, note: null, added_at: 'x', decided_at: 'x' };
    view(
      {
        succession: { ...base, state: 'forked', forked: true },
        preparation: { ...prep, c0: [{ ...item, number: 1, citation: 'lily:design/x.md' }, { ...item, number: 2, citation: 'lily:position/3' }] },
      },
      'c0',
    );
    const opens = (await screen.findAllByRole('button', { name: 'Open ›' })) as HTMLButtonElement[];
    expect(opens).toHaveLength(2);
    expect(opens[1].disabled).toBe(true);
    expect(screen.getByText('A position has no page of its own in the app.')).toBeTruthy();
    fireEvent.click(opens[0]);
    expect(useShell.getState().page).toBeNull();
    expect(useShell.getState().tab).toBe('records');
    expect(useShell.getState().stacks.records.at(-1)).toBe('doc/design/x.md');
  });

  it('lists the archive: models and judges named', async () => {
    vi.spyOn(api, 'successionArchive').mockResolvedValue({
      archive: {
        judgments: [
          { run: 4, question: 2, model: 'x/model', judge: 'witness:a1', category: 'DEVELOPMENT', argument: 'Grew.', evidence: 'Run 4', uncertainty: 'low', favorite: true },
        ],
        room: [{ number: 1, round: 1, party: 'witness:a1', act: 'say', text: 'I recommend x.', at: '2026-11-24T10:00:00Z' }],
        drafts: [{ draft: 1, party: 'witness:a1', model: 'x/model', basis: 'Because.', endorsed: ['witness:a1'] }],
      },
    });
    view({ succession: { ...base, state: 'withdrawn', ended_at: '2026-11-25T10:00:00Z' } }, 'outcome');
    expect(await screen.findByText('x/model')).toBeTruthy();
    expect(screen.getByText('DEV ★')).toBeTruthy();
    expect(screen.getByText('Grew.')).toBeTruthy();
    expect(screen.getByText('I recommend x.')).toBeTruthy();
    expect(screen.getByText(/recommends x\/model/)).toBeTruthy();
  });
});

describe('the deliberation', () => {
  it('puts its own four tabs where the shell’s were', async () => {
    vi.spyOn(api, 'succession').mockResolvedValue({ succession: { ...base, state: 'deliberating' }, preparation: prep });
    vi.spyOn(api, 'me').mockResolvedValue({ account_id: 'a1', email: 'w@example.com', residents: ['r1'] });
    vi.spyOn(api, 'householdContract').mockRejectedValue(new Error('no house'));
    vi.spyOn(api, 'judging').mockResolvedValue({ judging: null });
    vi.spyOn(api, 'room').mockResolvedValue({ room: { round: 2, opened_at: null, close_at: null, posts: [], drafts: [], channel: [], judgments: [] } });
    vi.spyOn(api, 'needsYou').mockResolvedValue([]);
    window.history.replaceState(null, '', '#/settings/succession/deliberation/thread');
    vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener: () => undefined, removeEventListener: () => undefined }));
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r1', slug: 'lily', name: 'Lily' }}>
          <Shell residentId="r1" residentName="Lily" waiting={0} onReconnect={() => undefined} renderTab={() => null} />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );
    const bar = await screen.findByRole('navigation', { name: 'Deliberation' });
    expect(bar.textContent).toContain('Recommendation');
    expect(bar.textContent).toContain('Panel');
    expect(screen.queryByRole('navigation', { name: 'Sections' })).toBeNull();
    expect(await screen.findByText('The thread')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /Recommendation/ }));
    expect(useShell.getState().pagePath).toBe('deliberation/recommendation');
  });
});

describe('the chat banner', () => {
  // The witness, 2026-11-26: the banner always opens the overview, even
  // with something of the succession waiting on you.
  it('always opens the overview', async () => {
    vi.spyOn(api, 'succession').mockResolvedValue({ succession: { ...base, state: 'forked' }, preparation: prep });
    vi.spyOn(api, 'needsYou').mockResolvedValue([
      { kind: 'succession_judge', ref: 1, since: '2026-11-26T18:00:00Z', screen: 'succession', long: false, about: { page: 'judge', words: '3 to judge' } },
    ]);
    useShell.setState({ page: null, pagePath: 'somewhere' });
    const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queries}>
        <SubjectContext.Provider value={{ id: 'r1', slug: 'lily', name: 'Lily' }}>
          <SuccessionBanner />
        </SubjectContext.Provider>
      </QueryClientProvider>,
    );
    expect(await screen.findByText('3 to judge')).toBeTruthy();
    fireEvent.click(screen.getByText('Back to the succession ›'));
    expect(useShell.getState().page).toBe('succession');
    expect(useShell.getState().pagePath).toBe('');
  });
});
