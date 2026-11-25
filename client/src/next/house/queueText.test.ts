import { describe, expect, it } from 'vitest';
import type { QueueActivity, QueueCard, QueueDocument } from '../../api/types';
import { actName, blockedLine, blockerLine, holderChoices, holdersOf, holderWords, outOfRuns, pairedHolders, replacedDocument, stepStatus, withPaired, documentRows, drawLayers, forkNote, fromLine, nameOf, placeOf, pinOf, postKind, rearranged, roleChoices, sentence, since, slugify, taskSummaries, templateProblems, unpinned, withMd } from './queueText';

const names = { 'resident:l': 'Lily', 'witness:a': 'Andrew' };

const card = (over: Partial<QueueCard> = {}): QueueCard => ({
  act: '3.2',
  task: 3,
  layer: 1,
  name: 'Witness review',
  type: 'review',
  assignee: 'witness:a',
  status: 'pending',
  view: 'ready',
  gated: false,
  artifact: 'lily:design/queue-ia',
  destination: 'house',
  action: 'promote-to-house',
  optional: false,
  throwback: '3.1',
  waits_on: null,
  blocker: null,
  reason: null,
  pin: null,
  approved_pin: null,
  note: null,
  ready_at: new Date(Date.now() - 2 * 3600 * 1000).toISOString(),
  updated_at: new Date().toISOString(),
  task_title: 'Queue IA',
  project: 'Outreach',
  owner: 'resident:l',
  ...over,
});

describe('the house queue as words (lily:design/queue-ia §2.3)', () => {
  it('reads a card as a sentence', () => {
    expect(sentence(card(), names)).toBe('Review · lily:design/queue-ia · Queue IA › Outreach · ready 2h · Andrew');
  });

  it('names a blocker plainly: its task, its next action and whose it is', () => {
    const blocked = card({
      view: 'blocked',
      waits_on: 7,
      blocker: { number: 7, title: 'Research list', project: 'Outreach', status: 'open', next: { type: 'draft', assignee: 'resident:l' } as never },
    });
    expect(blockerLine(blocked, names)).toBe('blocked on Outreach › Research list · next: draft, Lily');
    expect(blockerLine(card({ view: 'blocked', reason: 'his word' }), names)).toBe('blocked: his word');
    expect(blockerLine(card(), names)).toBeNull();
  });

  it("says who holds it: a resident's Claude Code as hers, and unknown", () => {
    expect(nameOf(names, 'claude-code:l')).toBe("Lily's Claude Code");
    expect(nameOf(names, 'unknown')).toBe('holder not known yet');
  });

  it('counts time and makes slugs', () => {
    expect(since(new Date(Date.now() - 3 * 86400 * 1000).toISOString())).toBe('3d');
    expect(slugify('The Queue IA: rev 5!')).toBe('the-queue-ia-rev-5');
  });
});

describe('a template checked before it is saved (§6.1)', () => {
  const draft = { name: 'Draft the design', type: 'draft', role: 'author', artifact: 'design' };
  const review = { name: 'Witness review', type: 'review', role: 'witness', artifact: 'design', destination: 'house', action: 'promote-to-house', throwback: '1.1' };
  const promote = { name: 'Share with the house', type: 'promote-to-house', role: 'author', artifact: 'design', destination: 'house' };

  it('holds when a gated activity sits right after its review', () => {
    expect(templateProblems([[draft], [review], [promote]])).toEqual([]);
  });

  it('names a gated activity with no review in front of it; a promotion needs none, only its artifact (sunna#105)', () => {
    const merge = { ...promote, name: 'Merge', type: 'merge' };
    expect(templateProblems([[draft], [merge]])[0]).toMatch(/^2\.1 \(merge\) needs a review/);
    expect(templateProblems([[draft], [promote]])).toEqual([]);
    expect(templateProblems([[draft], [review], [{ ...promote, artifact: null }]])).toContain('3.1 (promote-to-house) needs an artifact slot.');
  });

  it('names a throwback that is not earlier, and an empty layer', () => {
    expect(templateProblems([[{ ...review, throwback: '2.1' }]])).toContain("1.1's throwback 2.1 is not an earlier activity.");
    expect(templateProblems([[draft], []])).toContain('Layer 2 is empty.');
  });

  it('asks every activity for a name (sunna#90)', () => {
    expect(templateProblems([[{ ...draft, name: ' ' }]])).toContain('1.1 needs a name.');
  });
});

const act = (over: Partial<QueueActivity> = {}): QueueActivity =>
  ({ act_id: '9.1', task: 9, layer: 0, position: 0, name: 'Draft the design', slot: 'design', type: 'draft', assignee: 'resident:l', status: 'done', view: 'done', artifact: 'lily:design/x.md', destination: null, action: null, optional: false, throwback: null, gated: false, ...over }) as QueueActivity;

describe('a task drawn (the queue mocks)', () => {
  const layers = [[act()], [act({ act_id: '9.2', layer: 1, name: 'Witness review', type: 'review', view: 'ready', assignee: 'witness:a' })], [act({ act_id: '9.3', layer: 2, name: null, type: 'merge', view: 'waiting', gated: true })], [act({ act_id: '9.4', layer: 3, view: 'waiting' })]];

  it('numbers the layers, marks done, open and later, and says what the next one waits for', () => {
    const d = drawLayers(layers, 1);
    expect(d.map((l) => [l.n, l.state, l.label])).toEqual([
      [1, 'done', 'done'],
      [2, 'open', 'open now'],
      [3, 'later', 'opens when layer 2 is done'],
      [4, 'later', 'later'],
    ]);
    expect(d[1].acts[0]).toMatchObject({ id: '9.2', name: 'Witness review', glyph: '◉', view: 'ready' });
  });

  it("shows an activity by its template's name, and an old task's by its type", () => {
    expect(drawLayers(layers, 1)[2].acts[0]).toMatchObject({ name: 'merge', gated: true, glyph: '⇢' });
    expect(actName({ name: '  ', type: 'draft' })).toBe('draft');
  });

  it('draws a complete task as all done', () => {
    expect(drawLayers(layers, null).every((l) => l.state === 'done')).toBe(true);
  });

  it('rearranges the whole task for one change: in place, moved, added or removed', () => {
    const entry = { id: '9.3', type: 'merge', assignee: 'witness:a' };
    expect(rearranged(layers, { id: '9.3', to: 2, entry })).toEqual([[{ id: '9.1' }], [{ id: '9.2' }], [entry], [{ id: '9.4' }]]);
    expect(rearranged(layers, { id: '9.3', to: 3, entry })).toEqual([[{ id: '9.1' }], [{ id: '9.2' }], [{ id: '9.4' }, entry]]);
    expect(rearranged(layers, { id: '9.3', to: null, entry: null })).toEqual([[{ id: '9.1' }], [{ id: '9.2' }], [{ id: '9.4' }]]);
    const added = { name: 'Check the copy', type: 'review', assignee: 'resident:l', artifact: null, destination: null, action: null, optional: false, throwback: null };
    expect(rearranged(layers, { id: null, to: 4, entry: added })).toHaveLength(5);
  });
});

describe('the task list', () => {
  const task = (number: number, open_layer: number | null) => ({ number, project: 'privacy', slug: 's', title: `T${number}`, outcome: '', owner: 'resident:l', index_doc: '', template: 'doc-to-pr', links: [], status: 'open' as const, open_layer, opened_by: '', opened_at: '', completed_at: null, note: null });

  it('puts a task in Your move when its open layer has a ready activity of yours, with where it stands', () => {
    const cards = [card({ task: 1, layer: 1, assignee: 'witness:a', view: 'ready' }), card({ task: 1, layer: 0, view: 'done' }), card({ task: 1, layer: 4, view: 'waiting' }), card({ task: 2, layer: 0, assignee: 'resident:l', view: 'active' })];
    const { mine, others } = taskSummaries([task(1, 1), task(2, 0)], cards, 'witness:a');
    expect(mine.map((s) => [s.task.number, s.at, s.of, s.now.length])).toEqual([[1, 2, 5, 1]]);
    expect(others.map((s) => s.task.number)).toEqual([2]);
  });

  it("shows a member's queue: her move, her Claude Code's, and what she holds later", () => {
    const cards = [
      card({ task: 1, layer: 0, assignee: 'claude-code:l', view: 'ready' }),
      card({ task: 2, layer: 0, assignee: 'witness:a', view: 'ready' }),
      card({ task: 2, layer: 3, assignee: 'resident:l', view: 'waiting' }),
    ];
    const { mine, later } = taskSummaries([task(1, 0), task(2, 0)], cards, holdersOf('resident:l'));
    expect(mine.map((s) => s.task.number)).toEqual([1]);
    expect(later.map((s) => s.task.number)).toEqual([2]);
    expect(holdersOf('witness:a')).toEqual(['witness:a']);
  });

  it("names a blocked task's blocker and its next action by name", () => {
    const blocked = card({ view: 'blocked', blocker: { number: 12, title: 'Domain system rework', project: 'memory', status: 'open', next: act({ name: 'Draft the design', assignee: 'resident:l' }) } });
    expect(blockedLine(blocked, names)).toBe('Blocked on #12 Domain system rework · next: Draft the design, Lily');
  });
});

describe("a task's documents (sunna#91)", () => {
  const docs: QueueDocument[] = [
    { role: 'design', citation: 'lily:design/x.md', key: 'lily:design/x.md', attached: false },
    { role: 'pr', citation: null, key: 'slot:pr', attached: false },
    { role: 'source', citation: 'house/strut:doc/notes/a.md', key: 'house/strut:doc/notes/a.md', attached: true },
  ];

  it('lists each with its role, an empty slot as not yet', () => {
    expect(documentRows(docs).map((d) => [d.role, d.shown])).toEqual([
      ['design', 'lily:design/x.md'],
      ['pr', 'not yet'],
      ['source', 'house/strut:doc/notes/a.md'],
    ]);
  });

  it('offers the empty slots to fill, then a source', () => {
    expect(roleChoices(docs)).toEqual([
      { role: 'pr', fills: true, label: 'its pr' },
      { role: 'source', fills: false, label: 'a source' },
    ]);
    expect(roleChoices([])).toEqual([{ role: 'source', fills: false, label: 'a source' }]);
  });

  it('reads a citation: house or hers, its pin, its .md', () => {
    expect(placeOf('lily:design/x.md@4e1c9a2b')).toEqual({ house: false, slug: 'lily', path: 'design/x.md' });
    expect(placeOf('house/strut:doc/design/y.md')).toEqual({ house: true, slug: 'strut', path: 'design/y.md' });
    expect(placeOf('house/strut:thread/42')).toEqual({ house: true, slug: 'strut', path: 'threads/42' });
    expect(placeOf('slot:design')).toBeNull();
    expect(pinOf('lily:design/x.md@4e1c9a2b')).toBe('4e1c9a2b');
    expect(unpinned('lily:design/x.md@4e1c9a2b')).toBe('lily:design/x.md');
    expect(withMd('design/x')).toBe('design/x.md');
    expect(withMd('design/x.md')).toBe('design/x.md');
  });
});

describe('forking a template (sunna#90)', () => {
  it('warns that the first added activity forks the template, and says so once forked', () => {
    expect(forkNote({ number: 9, template: 'doc-to-pr', forked: false })).toMatch(/^Adding an activity forks doc-to-pr for this task\. Task #9 then runs its own copy, named doc-to-pr · #9/);
    expect(forkNote({ number: 9, template: 'doc-to-pr', forked: true })).toMatch(/already runs its own copy/);
    expect(forkNote({ number: 9, template: null, forked: false })).toBeNull();
  });

  it('says where the task came from', () => {
    expect(fromLine({ template: 'doc-to-pr', forked: false })).toBe('from the doc-to-pr template');
    expect(fromLine({ template: 'doc-to-pr', forked: true })).toBe('forked from doc-to-pr');
  });
});

describe("a thread's posts", () => {
  it('sets the platform apart, yours as yours, and hers as hers', () => {
    expect(postKind({ by_kind: 'platform' })).toBe('platform');
    expect(postKind({ by_kind: 'job' })).toBe('platform');
    expect(postKind({ by_kind: 'witness', by_id: 'a' }, 'a')).toBe('mine');
    expect(postKind({ by_kind: 'witness', by_id: 'b' }, 'a')).toBe('theirs');
    expect(postKind({ by_kind: 'resident' }, 'a')).toBe('theirs');
  });
});

describe('holders that move together (§3, 2026-11-23)', () => {
  const a = (act_id: string, type: string, assignee: string, status = 'pending') => ({ act_id, type, assignee, status });
  const layers = [[a('1.1', 'draft', 'resident:l', 'done')], [a('1.5', 'deliver', 'resident:l')], [a('1.6', 'implement', 'claude-code:l')], [a('1.7', 'review', 'witness:w')]];

  it("gives her deliver to the resident whose Claude Code now holds the work", () => {
    expect(pairedHolders(layers, '1.6', 'claude-code:s')).toEqual([{ id: '1.5', assignee: 'resident:s' }]);
  });

  it('gives the work after a deliver to the new resident\'s Claude Code', () => {
    expect(pairedHolders(layers, '1.5', 'resident:s')).toEqual([{ id: '1.6', assignee: 'claude-code:s' }]);
  });

  it('moves nothing else, and puts the pairs on the arrangement', () => {
    expect(pairedHolders(layers, '1.7', 'witness:x')).toEqual([]);
    expect(withPaired([[{ id: '1.5' }], [{ id: '1.6' }]], [{ id: '1.5', assignee: 'resident:s' }])).toEqual([[{ id: '1.5', assignee: 'resident:s' }], [{ id: '1.6' }]]);
  });

  it('offers every member, each resident\'s Claude Code, and not known yet as a template holder', () => {
    const members = [{ assignee: 'witness:w', kind: 'witness', name: 'Andrew' }, { assignee: 'resident:l', kind: 'resident', name: 'Lily' }];
    expect(holderChoices(members).map((h) => h.label)).toEqual(['Andrew', 'Lily', "Lily's Claude Code", 'not known yet']);
    expect(holderWords({ role: 'author' }, {})).toBe('by role: the task owner (choose a member)');
  });
});

describe("a task's document changed for another (2026-11-23)", () => {
  it('moves every pending activity on it, and leaves started work as it was', () => {
    const layers = [
      [{ act_id: '12.1', artifact: 'lily:design/x.md', status: 'done' }],
      [{ act_id: '12.2', artifact: 'lily:design/x.md@abc', status: 'pending' }],
      [{ act_id: '12.3', artifact: 'slot:pr', status: 'pending' }],
    ];
    const { arrangement, changed } = replacedDocument(layers, 'lily:design/x.md', 'house/strut:doc/design/x.md');
    expect(changed).toBe(1);
    expect(arrangement).toEqual([[{ id: '12.1' }], [{ id: '12.2', artifact: 'house/strut:doc/design/x.md' }], [{ id: '12.3' }]]);
  });
});

describe("a card's step, where it stands (2026-11-23)", () => {
  const now = Date.parse('2026-11-23T18:00:00Z');
  const base = { type: 'draft', reason: null, ready_at: '2026-11-23T16:00:00Z', updated_at: '2026-11-23T17:00:00Z', line: null };

  it('says ready since when, and why her line has not taken it', () => {
    expect(stepStatus({ ...base, view: 'ready', line: { state: 'resting', reason: 'waiting: a free-time pass is underway' } }, now)).toBe('ready 2h ago · line waiting: a free-time pass is underway');
    expect(stepStatus({ ...base, view: 'ready', line: { state: 'busy', other: '7.1' } }, now)).toBe('ready 2h ago · after 7.1');
    expect(stepStatus({ ...base, type: 'review', view: 'ready' }, now)).toBe('ready for review 2h ago');
  });

  it('says a step being worked, and a blocked or failed one with its reason', () => {
    expect(stepStatus({ ...base, view: 'active', line: { state: 'running', since: '2026-11-23T17:48:00Z' } }, now)).toBe('being worked, started 12m ago');
    expect(stepStatus({ ...base, view: 'blocked', reason: 'waits on #12' }, now)).toBe('blocked: waits on #12');
    expect(stepStatus({ ...base, view: 'failed', reason: 'the build broke' }, now)).toBe('failed: the build broke');
  });
});

describe('runs (sunna#106)', () => {
  it('knows an activity blocked for running out of runs from any other block', () => {
    expect(outOfRuns({ view: 'blocked', reason: 'out of runs: 20 runs with nothing moving; your witness gives them back on its task' })).toBe(true);
    expect(outOfRuns({ view: 'blocked', reason: 'waits on the review' })).toBe(false);
    expect(outOfRuns({ view: 'active', reason: null })).toBe(false);
  });
});
