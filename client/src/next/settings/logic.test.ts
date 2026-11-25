import { describe, expect, it } from 'vitest';
import { RequestFailed } from '../../api/client';
import type { RegressionCard, RegressionRunDetail, RoutesData, WorkQueue } from '../../api/types';
import { answerLine, argumentsText, capLine, lines, loopLine, routeOk, saidOf, setupCommand, span, withCard } from './logic';

const queue = (over: Partial<WorkQueue> = {}): WorkQueue => ({
  running_since: null,
  running_act: null,
  running_task: null,
  rested: null,
  rested_at: null,
  runs_today: 1,
  runs_a_day: 6,
  budget: null,
  ...over,
});

describe('the work line', () => {
  it('says what runs, for how long, and what is left of its cap (sunna#86, #102)', () => {
    const now = Date.parse('2026-11-13T12:00:00Z');
    const running = queue({ running_act: '12.1', running_task: 12, running_since: '2026-11-13T10:30:00Z', budget: { cap: 5e9, spent: 1e9, left: 4e9, period: 'day' } });
    expect(loopLine('Mira', running, now)).toBe('Running activity 12.1 of task #12, for 1h 30m. 1 of 6 runs today; work budget: $4.00 left of $5.00 a day.');
    expect(loopLine('Mira', queue({ rested: 'holding: nothing is ready' }))).toBe('Resting: holding: nothing is ready. 1 of 6 runs today; work budget: no cap.');
    expect(loopLine('Mira', queue())).toBe("Mira's line has not run yet. 1 of 6 runs today; work budget: no cap.");
  });

  it('says a span in its largest two units', () => {
    expect(span(30)).toBe('under a minute');
    expect(span(45 * 60)).toBe('45m');
    expect(span(2 * 3600)).toBe('2h');
    expect(span(26 * 3600 + 60)).toBe('1d 2h');
  });
});

describe('the ledger, routes and reader', () => {
  it('says a line with no cap has no limit, and a stopped one', () => {
    expect(capLine({ cap: null, period: 'month', spent: '1.20', exceeded: false })).toBe('$1.20 of no limit');
    expect(capLine({ cap: '5.00', period: 'month', spent: '5.02', exceeded: true })).toBe('$5.02 of $5.00 a month, stopped');
  });

  it('takes a route only through a standing profile into a landing kind', () => {
    const data: RoutesData = {
      routes: [{ key: 'gmail', label: 'Mail', direction: 'source', profile: 'p', kind: 'letters', cadence: 'on_wait', runner: 'reader', built_in: true, state: 'ready', why: null }],
      runs: [],
      profiles: [
        { key: 'p', label: 'P', origin: 'https://a.b', signed_in_as: null, browser: null, sites: [], connector: null, seeded: false, revoked: false, routes: [] },
        { key: 'gone', label: 'G', origin: 'https://c.d', signed_in_as: null, browser: null, sites: [], connector: null, seeded: false, revoked: true, routes: [] },
      ],
      landing: ['notes'],
    };
    const draft = { key: 'news', prompt: 'the headlines', profile: 'p', kind: 'notes' };
    expect(routeOk(data, draft)).toBe(true);
    expect(routeOk(data, { ...draft, key: 'gmail' })).toBe(false);
    expect(routeOk(data, { ...draft, profile: 'gone' })).toBe(false);
    expect(routeOk(data, { ...draft, kind: 'letters' })).toBe(false);
    expect(routeOk(data, { ...draft, prompt: '  ' })).toBe(false);
  });

  it('reads one site a line', () => {
    expect(lines(' https://a.org \n\n*\n')).toEqual(['https://a.org', '*']);
  });
});

describe('notifications and refusals', () => {
  it("says the account's answer", () => {
    expect(answerLine(null, null)).toMatch(/Not answered yet/);
    expect(answerLine('declined', '2026-11-10T10:00:00Z')).toMatch(/^You said no thanks on .*; no device asks again/);
    expect(answerLine('subscribed', null)).toBe('You said yes.');
  });

  it("says the server's meaning and remedy", () => {
    expect(saidOf(new RequestFailed(422, { kind: 'x', meaning: 'That key is not valid.', remedy: 'Paste it again.' }))).toBe('That key is not valid. Paste it again.');
    expect(saidOf(new Error('offline'))).toBe('offline');
  });
});

describe('a run', () => {
  const card = (ref: string, test: number): RegressionCard => ({
    card_ref: ref,
    test_number: test,
    behaviour_number: null,
    commitment_number: null,
    content: 'hi',
    refusal: false,
    failure: null,
    grade: null,
    favourite: false,
    model: null,
    trace: [],
  });
  const detail: RegressionRunDetail = {
    run: { ref: 'r1', models: ['a/b'], tests: [1, 2], behaviours: [], commitments: [], started_at: '', finished_at: null, failed_at: null, failure: null, state: 'running', cards: 1 },
    cards: [card('c2', 2)],
    results: [],
  };

  it('puts a live card where a reload would, once, and only in its own run', () => {
    const next = withCard(detail, 'r1', card('c1', 1));
    expect(next?.cards.map((c) => c.card_ref)).toEqual(['c1', 'c2']);
    expect(next?.run.cards).toBe(2);
    expect(withCard(next, 'r1', card('c1', 1))).toBe(next);
    expect(withCard(detail, 'other', card('c1', 1))).toBe(detail);
  });

  it('lays out arguments that are an object, and says when there are none', () => {
    expect(argumentsText('{"path":"a.md"}')).toBe('{\n  "path": "a.md"\n}');
    expect(argumentsText('{}')).toBe('with nothing');
    expect(argumentsText('null')).toBe('with nothing');
    expect(argumentsText('not json')).toBe('not json');
  });
});

describe('setupCommand (dioscuri#8)', () => {
  it('is the same command for any resident, slug and id in it, never a token', () => {
    expect(setupCommand('https://o.example/', 'writer', 'scarlett', 'r2')).toBe('bash <(curl -fsSL https://o.example/setup.sh) writer --slug scarlett --resident r2');
    expect(setupCommand('https://o.example', 'writer', 'lily', 'r1')).toBe('bash <(curl -fsSL https://o.example/setup.sh) writer --slug lily --resident r1');
  });

  it("adds a reader's handle and address, quoted, and only for the reader", () => {
    expect(setupCommand('https://o.example', 'reader', 'wren', 'r3', { substack: 'wren', email: "o'k@x.test" })).toBe(
      "bash <(curl -fsSL https://o.example/setup.sh) reader --slug wren --resident r3 --substack 'wren' --email 'o'\\''k@x.test'",
    );
    expect(setupCommand('https://o.example', 'writer', 'wren', 'r3', { substack: 'wren' })).not.toContain('--substack');
  });
});
