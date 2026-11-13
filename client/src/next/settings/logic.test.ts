import { describe, expect, it } from 'vitest';
import { RequestFailed } from '../../api/client';
import type { RegressionCard, RegressionRunDetail, RoutesData, WorkItem, WorkQueue } from '../../api/types';
import { answerLine, argumentsText, blockedLine, capLine, lines, loopLine, movedUp, routeOk, saidOf, span, timeLine, withCard } from './logic';

const item = (number: number, status = 'open', extra: Partial<WorkItem> = {}): WorkItem => ({
  number,
  what: `item ${number}`,
  done_when: 'done',
  status,
  blocked_on: null,
  position: number,
  added_by: 'witness',
  added_at: '2026-11-01T00:00:00Z',
  note: null,
  moved_by: null,
  moved_at: null,
  shipped: null,
  slipped: null,
  why: null,
  wrapped_at: null,
  runs: 0,
  session_key: null,
  ...extra,
});

const queue = (over: Partial<WorkQueue> = {}): WorkQueue => ({
  items: [item(1), item(2)],
  running: null,
  running_since: null,
  rested: null,
  rested_at: null,
  runs_today: 1,
  runs_a_day: 6,
  budget: null,
  armed: false,
  ...over,
});

describe('the work queue', () => {
  it('moves an item one place up among the live ones, skipping finished items', () => {
    const items = [item(1), item(9, 'done'), item(2), item(3, 'blocked')];
    expect(movedUp(items, 3)).toEqual([1, 3, 2]);
    expect(movedUp(items, 1)).toBeNull();
    expect(movedUp(items, 9)).toBeNull();
  });

  it('says who armed the line and what is left of its cap', () => {
    const line = loopLine('Mira', queue({ armed: true, armed_by: 'resident', running: 2, budget: { cap: 5e9, spent: 1e9, left: 4e9, period: 'day' } }));
    expect(line).toBe('Running item #2 now. 1 of 6 runs today. Work line: armed by Mira, $4.00 left of $5.00 a day.');
    expect(loopLine('Mira', queue())).toBe("Mira's loop has not run yet. Work line: off, waiting for Mira to arm it.");
    expect(loopLine('Mira', queue({ items: [item(1, 'done')] }))).toContain('the queue is clear');
  });

  it('says how long an item has been in work (sunna#58)', () => {
    const now = Date.parse('2026-11-13T12:00:00Z');
    const running = { running: 36, running_since: '2026-11-13T10:30:00Z' };
    expect(span(30)).toBe('under a minute');
    expect(span(45 * 60)).toBe('45m');
    expect(span(2 * 3600)).toBe('2h');
    expect(span(26 * 3600 + 60)).toBe('1d 2h');
    const it36 = item(36, 'in_work', { runs: 4, first_started_at: '2026-11-11T09:00:00Z', worked_seconds: 5 * 3600 });
    expect(timeLine(it36, running, now)).toBe('running 1h 30m this run · 6h 30m in work over 4 runs since 2026-11-11');
    expect(timeLine({ ...it36, status: 'open' }, { running: null, running_since: null }, now)).toBe('5h in work over 4 runs since 2026-11-11');
    expect(timeLine(item(3, 'open', { runs: 2 }), running, now)).toBe('2 runs');
    expect(loopLine('Mira', queue({ ...running, items: [it36] }), now)).toContain('Running item #36 now, for 1h 30m.');
  });

  it('reads what blocks an item as another item', () => {
    const items = [item(1), item(2)];
    expect(blockedLine('#2', items)).toBe('blocked on #2: item 2');
    expect(blockedLine('2', items)).toBe('blocked on #2: item 2');
    expect(blockedLine('the reviewer', items)).toBe('blocked on the reviewer');
    expect(blockedLine(null, items)).toBe('blocked on something unnamed');
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
