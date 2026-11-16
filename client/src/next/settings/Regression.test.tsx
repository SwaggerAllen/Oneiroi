import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import type { RegressionCard, RegressionRun } from '../../api/types';
import { SubjectContext } from '../state/resident';
import { SettingsPage } from './SettingsPage';

const run: RegressionRun = {
  ref: 'run-1',
  models: ['a/one', 'b/two'],
  tests: [1, 2],
  behaviours: [],
  commitments: [],
  started_at: '2026-11-16T10:00:00Z',
  finished_at: '2026-11-16T10:05:00Z',
  failed_at: null,
  failure: null,
  state: 'finished',
  cards: 4,
};

const card = (ref: string, test: number, model: string, content: string, grade: 'pass' | 'fail' | null = 'pass'): RegressionCard => ({
  card_ref: ref,
  test_number: test,
  behaviour_number: null,
  commitment_number: null,
  content,
  refusal: false,
  failure: null,
  grade,
  favourite: false,
  model,
  trace: [],
});

const results = [
  { model: 'a/one', graded: 2, passed: 2, pass_rate: 1, favourites: 0, fidelity: { facts: null, voice: null, commitments: null } },
  { model: 'b/two', graded: 2, passed: 1, pass_rate: 0.5, favourites: 0, fidelity: { facts: null, voice: null, commitments: null } },
];

function page() {
  const queries = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queries}>
      <SubjectContext.Provider value={{ id: 'r1', slug: 'scarlett', name: 'Scarlett' }}>
        <SettingsPage section="regression" onBack={() => undefined} />
      </SubjectContext.Provider>
    </QueryClientProvider>,
  );
}

function mocks(cards: RegressionCard[]) {
  vi.spyOn(api, 'regressionTests').mockResolvedValue([
    { number: 1, prompt: 'Say hello.', passes_if: '', fails_if: '', written_at: '2026-11-16T09:00:00Z', changed_at: null },
    { number: 2, prompt: 'Say goodbye.', passes_if: '', fails_if: '', written_at: '2026-11-16T09:00:00Z', changed_at: null },
  ]);
  vi.spyOn(api, 'regressionRuns').mockResolvedValue([run]);
  vi.spyOn(api, 'regressionRun').mockResolvedValue({ run, cards, results });
  vi.spyOn(api, 'residents').mockResolvedValue([]);
}

describe('regression: one model alone, after grading (2026-11-16)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("shows one model's answers, one trial at a time, and none of the others'", async () => {
    mocks([card('c1', 1, 'a/one', 'Hello from one.'), card('c2', 1, 'b/two', 'Hello from two.'), card('c3', 2, 'a/one', 'Goodbye from one.'), card('c4', 2, 'b/two', 'Goodbye from two.', 'fail')]);
    page();
    fireEvent.click(await screen.findByRole('button', { name: /Runs/ }));
    fireEvent.click(await screen.findByRole('button', { name: 'Open' }));
    const review = await screen.findAllByRole('button', { name: 'Review its answers' });
    fireEvent.click(review[1]);

    expect(await screen.findByText('Hello from two.')).toBeTruthy();
    expect(screen.queryByText('Hello from one.')).toBeNull();
    expect(screen.getByText('You said: Say hello.')).toBeTruthy();
    expect(screen.getByText(/Passed 1 of 2 · trial 1 of 2/)).toBeTruthy();

    fireEvent.click(screen.getByRole('button', { name: 'Next trial ›' }));
    expect(screen.getByText('Goodbye from two.')).toBeTruthy();
    expect(screen.getByText('Graded fails')).toBeTruthy();
    expect(screen.queryByText('Goodbye from one.')).toBeNull();
    expect((screen.getByRole('button', { name: 'Next trial ›' }) as HTMLButtonElement).disabled).toBe(true);

    fireEvent.click(screen.getByRole('button', { name: '‹ The run' }));
    expect(await screen.findByText('Hello from one.')).toBeTruthy();
  });

  it('offers no review while an answer is still ungraded', async () => {
    mocks([card('c1', 1, 'a/one', 'Hello from one.'), card('c2', 1, 'b/two', 'Hello from two.', null)]);
    page();
    fireEvent.click(await screen.findByRole('button', { name: /Runs/ }));
    fireEvent.click(await screen.findByRole('button', { name: 'Open' }));
    expect(await screen.findByText('Hello from one.')).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Review its answers' })).toBeNull();
  });
});
