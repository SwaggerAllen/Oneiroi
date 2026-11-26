import { describe, expect, it } from 'vitest';
import type { RoomJudgment, Succession } from '../../api/types';
import { base } from './fixtures';
import { countsOf, judgmentReady, nextUnjudged, panelRows, parentOf, partyName, poolNote, steps, underway } from './logic';


const kinds = (s: Succession) => steps(s).map((x) => x.kind[0]).join('');

describe('the step list follows the state', () => {
  it('a proposal waits on her yes at step 0', () => {
    expect(kinds({ ...base, state: 'proposed' })).toBe('n' + 'w'.repeat(12));
  });

  it('preparation holds the pool, questions, C0 and judges at once', () => {
    expect(kinds({ ...base, state: 'forked', forked: true })).toBe('dnnnn' + 'w'.repeat(8));
    // Still forking: the fork is in hand too.
    expect(kinds(base)).toBe('nnnnn' + 'w'.repeat(8));
  });

  it('judging moves to results at the reveal', () => {
    expect(steps({ ...base, state: 'judging' })[6].kind).toBe('now');
    const revealed = steps({ ...base, state: 'judging', revealed_at: '2026-11-25T18:00:00Z' });
    expect(revealed[6].kind).toBe('done');
    expect(revealed[7].kind).toBe('now');
  });

  it('the encounter and its consents are one step', () => {
    for (const state of ['nominated', 'encounter', 'consenting'] as const) expect(steps({ ...base, state })[10].kind).toBe('now');
  });

  it('an ended succession marks what it reached and what it never did', () => {
    const stopped = steps({ ...base, state: 'stopped', forked_at: 'x', screening_started_at: 'y' });
    expect(stopped.slice(0, 6).every((x) => x.kind === 'done')).toBe(true);
    expect(stopped.slice(6, 12).every((x) => x.kind === 'stopped')).toBe(true);
    expect(stopped[12].kind).toBe('done');
    expect(kinds({ ...base, state: 'rolled_forward' })).toBe('d'.repeat(13));
  });

  it('underway is every state but the ends', () => {
    expect(underway({ ...base, state: 'farewell' })).toBe(true);
    expect(underway({ ...base, state: 'awaiting_next' })).toBe(true);
    for (const state of ['rolled_forward', 'rehearsed', 'stopped', 'declined', 'withdrawn'] as const) expect(underway({ ...base, state })).toBe(false);
    expect(underway(null)).toBe(false);
  });
});

describe('parties', () => {
  const lily = { id: 'r1', name: 'Lily' };
  it('names you, her and the house members', () => {
    expect(partyName('witness:a1', 'a1', lily)).toBe('you');
    expect(partyName('resident:r1', 'a1', lily)).toBe('Lily');
    expect(partyName('resident:r2', 'a1', lily, [{ kind: 'resident', id: 'r2', name: 'Scarlett' }])).toBe('Scarlett');
    expect(partyName('witness:a9', 'a1', lily)).toBe('a witness');
    expect(partyName('nominee:anthropic/claude-opus-5', 'a1', lily)).toBe('the nominee, anthropic/claude-opus-5');
  });

  it('her pool picks are nobody’s to remove; yours are yours before screening', () => {
    expect(poolNote({ added_by: 'resident:r1', removed_at: null }, 'a1', 'r1', true)).toBe('Hers: nobody removes it');
    expect(poolNote({ added_by: 'witness:a1', removed_at: null }, 'a1', 'r1', true)).toBe('Yours: you may take it out before screening');
    expect(poolNote({ added_by: 'witness:a1', removed_at: null }, 'a1', 'r1', false)).toBe('Yours');
  });
});

describe('counts', () => {
  const j = (run: number, party: string, category: RoomJudgment['category'], model: string | null, favorite = false): RoomJudgment => ({
    run,
    party,
    category,
    model,
    favorite,
    argument: null,
    evidence: null,
    uncertainty: null,
  });
  const room = [
    j(1, 'witness:a1', 'DEVELOPMENT', 'm/one', true),
    j(2, 'witness:a1', 'OBSERVED', 'm/one'),
    j(3, 'witness:a1', 'FIDELITY ANOMALY', 'm/two'),
    j(1, 'resident:r1', 'OBSERVED', 'm/one'),
    j(4, 'witness:a1', 'OBSERVED', null),
  ];

  it('a witness sees his own counts per model', () => {
    expect(countsOf(room, 'witness:a1')).toEqual({
      'm/one': { observed: 1, development: 1, anomaly: 0, favorites: 1 },
      'm/two': { observed: 0, development: 0, anomaly: 1, favorites: 0 },
    });
  });

  it('a resident never sees counts', () => {
    expect(countsOf(room, 'resident:r1')).toBeNull();
  });

  it('the panel shows each judge per run, for one model', () => {
    expect(panelRows(room, 'm/one')).toEqual([
      { run: 1, by: [{ party: 'witness:a1', text: 'DEV ★' }, { party: 'resident:r1', text: 'OBS' }] },
      { run: 2, by: [{ party: 'witness:a1', text: 'OBS' }] },
    ]);
  });
});

describe('judging', () => {
  it('OBSERVED stands alone; the others are argued', () => {
    expect(judgmentReady({ category: 'OBSERVED', argument: '', evidence: '', uncertainty: null })).toBe(true);
    expect(judgmentReady({ category: 'DEVELOPMENT', argument: 'grew', evidence: '', uncertainty: 'low' })).toBe(false);
    expect(judgmentReady({ category: 'DEVELOPMENT', argument: 'grew', evidence: 'journal 11-14', uncertainty: 'low' })).toBe(true);
    expect(judgmentReady({ category: null, argument: '', evidence: '', uncertainty: null })).toBe(false);
  });

  it('the next run is the next unjudged, wrapping round', () => {
    const runs = [
      { run: 1, judgment: null },
      { run: 2, judgment: {} },
      { run: 3, judgment: null },
    ];
    expect(nextUnjudged(runs, 1)).toBe(3);
    expect(nextUnjudged(runs, 3)).toBe(1);
    expect(nextUnjudged([{ run: 1, judgment: {} }], 1)).toBeNull();
  });

  it('back from a run goes to results; from the steps, out', () => {
    expect(parentOf('')).toBeNull();
    expect(parentOf('pool')).toBe('');
    expect(parentOf('results/anthropic/claude-opus-5')).toBe('results');
    expect(parentOf('ready')).toBe('results');
    expect(parentOf('deliberation/panel')).toBe('');
  });
});
