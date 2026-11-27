import { describe, expect, it } from 'vitest';
import type { RoomJudgment, Succession } from '../../api/types';
import { base } from './fixtures';
import { archiveByModel, countsOf, isSuccessionNeed, judgmentReady, backOf, needHref, nextOf, nextUnjudged, panelRows, parentOf, partyName, placeOf, poolNote, quiet, quietWords, steps, underway } from './logic';


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
    expect(poolNote({ added_by: 'resident:r1', removed_at: null }, 'a1', 'r1', true)).toBe('Hers: only she takes it out');
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

describe('a C0 citation opens where the app opens it', () => {
  it('a document in Records, a root file too', () => {
    expect(placeOf('lily:design/x.md', 'lily')).toEqual({ to: { tab: 'records', path: 'doc/design/x.md' } });
    expect(placeOf('lily:SOUL.md', 'lily')).toEqual({ to: { tab: 'records', path: 'doc/SOUL.md' } });
    expect(placeOf('lily:etymologies/oneiric', 'lily')).toEqual({ to: { tab: 'records', path: 'doc/etymologies/oneiric.md' } });
  });

  it('a bookmark in its peek, a turn in the conversation, a journal entry on its day', () => {
    expect(placeOf('lily:bookmark/12', 'lily')).toEqual({ to: { tab: 'records', path: 'cite/bookmark/12' } });
    expect(placeOf('lily:transcript/abc-_9/t42', 'lily')).toEqual({ to: { tab: 'chat', path: 'turn/abc-_9/t42' } });
    expect(placeOf('lily:journal/2026-11-20/4', 'lily')).toEqual({ to: { tab: 'time', path: 'day/2026-11-20' } });
    expect(placeOf('lily:letter/7', 'lily')).toEqual({ to: { tab: 'chat', path: 'mail' } });
  });

  it('says why when there is nowhere to open', () => {
    expect('reason' in placeOf('lily:position/3', 'lily')).toBe(true);
    expect('reason' in placeOf('lily:scene/3', 'lily')).toBe(true);
    expect('reason' in placeOf('lily:transcript/abc', 'lily')).toBe(true);
    expect('reason' in placeOf('mira:design/x.md', 'lily')).toBe(true);
    expect('reason' in placeOf('nothing', 'lily')).toBe(true);
  });
});

describe("the room's quiet clock", () => {
  const at = (min: number) => new Date(Date.parse('2026-11-26T10:00:00Z') + min * 60_000).toISOString();
  const post = (n: number, min: number) => ({ number: n, round: 1, party: 'witness:a1', act: 'say' as const, text: 'x', at: at(min) });

  it('counts from the latest post', () => {
    const q = quiet({ opened_at: at(0), posts: [post(2, 5), post(1, 1)] }, Date.parse(at(9)));
    expect(q).toEqual({ quiet: 4, left: 6 });
    expect(quietWords(q as { quiet: number; left: number })).toBe('quiet 4 min · at 10 everyone is woken');
  });

  it('counts from the opening when nobody has posted', () => {
    expect(quiet({ opened_at: at(0), posts: [] }, Date.parse(at(3)) + 59_000)).toEqual({ quiet: 3, left: 7 });
    expect(quiet({ opened_at: null, posts: [] }, Date.now())).toBeNull();
  });

  it('at ten, everyone is being woken', () => {
    const q = quiet({ opened_at: at(0), posts: [] }, Date.parse(at(12)));
    expect(q).toEqual({ quiet: 12, left: 0 });
    expect(quietWords(q as { quiet: number; left: number })).toContain('being woken');
  });
});

describe('the bell entries of the succession', () => {
  it('open their page under the succession', () => {
    expect(needHref({ about: { page: 'deliberation/thread' } })).toBe('#/settings/succession/deliberation/thread');
    expect(needHref({ about: { page: 'c0' } })).toBe('#/settings/succession/c0');
    expect(needHref({ about: {} })).toBe('#/settings/succession');
    expect(isSuccessionNeed({ kind: 'succession_goodbye' })).toBe(true);
    expect(isSuccessionNeed({ kind: 'ask' })).toBe(false);
  });
});

describe('the archive', () => {
  it('groups judgments by model, then run, every judge together', () => {
    const j = (run: number, model: string, judge: string) => ({
      run,
      question: run,
      model,
      judge,
      category: 'OBSERVED' as const,
      argument: null,
      evidence: null,
      uncertainty: null,
      favorite: false,
    });
    const out = archiveByModel([j(3, 'b/m', 'witness:a1'), j(1, 'a/m', 'witness:a1'), j(1, 'a/m', 'resident:r1'), j(2, 'b/m', 'witness:a1')]);
    expect(out.map((m) => m.model)).toEqual(['b/m', 'a/m']);
    expect(out[0].runs.map((r) => r.run)).toEqual([2, 3]);
    expect(out[1].runs[0].by).toHaveLength(2);
  });
});

describe('Next (the witness, 2026-11-27)', () => {
  const forked = { ...base, state: 'forked', forked: true, forked_at: '2026-11-26T20:00:00Z' } as never;

  it('goes from the overview to the first step reached, and on through preparation', () => {
    expect(nextOf('', forked)).toEqual({ page: 'pool', name: 'The pool' });
    expect(nextOf('pool', forked)?.page).toBe('questions');
    expect(nextOf('c0', forked)?.page).toBe('judges');
  });

  it('stops at the last step reached, outside the steps, and before the fork', () => {
    expect(nextOf('judges', forked)).toBeNull();
    expect(nextOf('log', forked)).toBeNull();
    expect(nextOf('pool', { ...base, state: 'open', forked: false, forked_at: null } as never)).toBeNull();
  });

  it('counts a model\'s runs and ready as results', () => {
    const judging = { ...base, state: 'deliberating', forked: true, forked_at: 'x', revealed_at: 'y' } as never;
    expect(nextOf('results/a%2Fone', judging)?.page).toBe('deliberation');
    expect(nextOf('ready', judging)?.page).toBe('deliberation');
  });
});

describe('Back is the previous step (the witness, 2026-11-27)', () => {
  const forked = { ...base, state: 'forked', forked: true, forked_at: '2026-11-26T20:00:00Z' } as never;
  const judging = { ...base, state: 'deliberating', forked: true, forked_at: 'x', revealed_at: 'y' } as never;

  it('steps back through the pages, and from the first to the overview', () => {
    expect(backOf('questions', forked)).toBe('pool');
    expect(backOf('judges', forked)).toBe('c0');
    expect(backOf('pool', forked)).toBe('');
    expect(backOf('deliberation/thread', judging)).toBe('results');
  });

  it('takes a page under a step to its step, the log to the overview, the overview out', () => {
    expect(backOf('results/a%2Fone', judging)).toBe('results');
    expect(backOf('ready', judging)).toBe('results');
    expect(backOf('log', forked)).toBe('');
    expect(backOf('', forked)).toBeNull();
  });
});

describe('a shared memory in C0 (janus#43)', () => {
  it("opens a house record in the house's records (every judge is a member)", () => {
    expect(placeOf('house/rook:thread/abc@1234567890ab', 'lily')).toEqual({ to: { tab: 'records', path: 'doc/threads/abc' }, house: true });
    expect(placeOf('house/rook:doc/plans/week.md', 'lily')).toEqual({ to: { tab: 'records', path: 'doc/plans/week.md' }, house: true });
    expect(placeOf('house/rook:elsewhere', 'lily')).toEqual({ reason: 'Not a house citation the app can follow.' });
  });
});
