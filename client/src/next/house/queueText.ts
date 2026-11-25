import type { QueueActivity, QueueCard, QueueDocument, QueueEditEntry, QueueTask } from '../../api/types';

/** Assignee to the house's name for it. */
export type Names = Record<string, string>;

export const pin = (p: string | null) => (p ? `@${p.slice(0, 7)}` : '');

/** A resident's Claude Code (`claude-code:<id>`) runs on her memories, so it is named as hers (§3). */
export const nameOf = (names: Names, a: string): string => {
  if (a === 'unknown') return 'holder not known yet';
  if (a.startsWith('claude-code:')) {
    const hers = names[`resident:${a.slice('claude-code:'.length)}`];
    return hers ? `${hers}'s Claude Code` : 'Claude Code';
  }
  return names[a] ?? a;
};

/** How long ago, in the card's few characters: "2h", "3d". */
export function since(iso: string | null, now = Date.now()): string {
  if (!iso) return '';
  const s = Math.max(0, (now - new Date(iso).getTime()) / 1000);
  if (s < 3600) return `${Math.max(1, Math.round(s / 60))}m`;
  if (s < 86400) return `${Math.round(s / 3600)}h`;
  return `${Math.round(s / 86400)}d`;
}

/** The card's sentence: Review · design/x @a1b2c3 · Task › Project · ready 2h. */
export function sentence(c: QueueCard, names: Names): string {
  const art = c.artifact ? ` · ${c.artifact}${pin(c.approved_pin ?? c.pin)}` : '';
  const state = c.view === 'ready' ? `ready ${since(c.ready_at)}` : c.view;
  return `${c.type[0].toUpperCase()}${c.type.slice(1)}${c.gated ? ' (gated)' : ''}${art} · ${c.task_title} › ${c.project} · ${state} · ${nameOf(names, c.assignee)}`;
}

/** The blocked card's second line, plainly (§1). */
export function blockerLine(c: QueueCard, names: Names): string | null {
  if (c.view === 'failed') return `failed: ${c.reason ?? ''}`;
  if (c.view !== 'blocked') return null;
  if (!c.blocker) return `blocked: ${c.reason ?? ''}`;
  const next = c.blocker.next ? `${c.blocker.next.type}, ${nameOf(names, c.blocker.next.assignee)}` : 'nothing open';
  return `blocked on ${c.blocker.project} › ${c.blocker.title} · next: ${next}`;
}

export const slugify = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64);

// ---- templates (sunna#83, #88) ----

/** The activity types a review must stand in front of (§6.1), as the server's `gated_types/0`; promote-to-house no longer (sunna#105). */
export const GATED = ['send', 'publish', 'spend', 'merge'];

/** The activity types that act on a named artifact, as the server's `artifact_types/0`. */
export const ARTIFACT_BOUND = [...GATED, 'promote-to-house'];

/** The roles a template's activity is held by, resolved to members when a task opens. */
export const ROLES = ['author', 'witness', 'peer', 'builder', 'unknown'] as const;

/** One activity of a template as the editor holds it. */
export interface TemplateSpec {
  /** What every task made from the template calls it (sunna#90). */
  name: string;
  type: string;
  /** Who holds it in every task made from the template (sunna#93): a member, a Claude Code, or unknown. */
  assignee?: string | null;
  /** A holder by role, on a template written before sunna#93; resolved as it was until a member is chosen. */
  role?: string | null;
  artifact?: string | null;
  destination?: string | null;
  action?: string | null;
  optional?: boolean;
  throwback?: string | null;
}

/** "2.1": layer 2's first activity, the position a throwback names. */
export const position = (layer: number, index: number) => `${layer + 1}.${index + 1}`;

/**
 * What the server will refuse, said before saving (the shape rule, §6.1):
 * an activity on an artifact needs its slot; a gated one, in the layer directly
 * before it, a review of the same slot naming its destination and
 * action; a throwback names an activity in an earlier layer. One line per
 * problem, by position.
 */
export function templateProblems(layers: TemplateSpec[][]): string[] {
  const problems: string[] = [];
  if (layers.length === 0) problems.push('A template needs at least one layer.');
  layers.forEach((layer, i) => {
    if (layer.length === 0) problems.push(`Layer ${i + 1} is empty.`);
    layer.forEach((s, j) => {
      const at = position(i, j);
      if (!s.name.trim()) problems.push(`${at} needs a name.`);
      if (!s.type.trim()) problems.push(`${at} needs a verb.`);
      if (ARTIFACT_BOUND.includes(s.type) && !s.artifact) problems.push(`${at} (${s.type}) needs an artifact slot.`);
      if (GATED.includes(s.type)) {
        const before = i > 0 ? layers[i - 1] : [];
        const reviewed = before.some((r) => r.type === 'review' && (r.artifact ?? null) === (s.artifact ?? null) && (r.destination ?? null) === (s.destination ?? null) && r.action === s.type);
        if (!reviewed) problems.push(`${at} (${s.type}) needs a review of the same artifact, for ${s.type}${s.destination ? ` to ${s.destination}` : ''}, in the layer before it.`);
      }
      if (s.throwback) {
        const [l] = s.throwback.split('.').map(Number);
        if (!(l >= 1 && l <= i)) problems.push(`${at}'s throwback ${s.throwback} is not an earlier activity.`);
      }
    });
  });
  return problems;
}

// ---- the redesign (sunna#90, #91; design/document-threads.md) ----

/** An activity's name is its template's (sunna#90); an old task's activity, opened before names, shows its type. */
export const actName = (a: { name?: string | null; type: string }) => a.name?.trim() || a.type;

/** Each type's glyph in the drawn layers. */
const GLYPHS: Record<string, string> = {
  draft: '✎',
  review: '◉',
  'promote-to-house': '↥',
  promote: '↥',
  deliver: '→',
  implement: '⌘',
  merge: '⇢',
  send: '✉',
  publish: '⇪',
  spend: '¤',
};
export const glyph = (type: string) => GLYPHS[type] ?? '•';

/** What approving a review lets happen, by the gated action it names. */
export const LETS: Record<string, string> = { 'promote-to-house': 'it be shared', merge: 'it be merged', send: 'it be sent', publish: 'it be published', spend: 'it be spent' };

/**
 * Who a template's activity can be held by (sunna#93): each member, each
 * resident's Claude Code, and not known yet. Fixed in the template: never
 * who opens the task.
 */
export function holderChoices(members: { assignee: string; kind: string; name: string }[]): { value: string; label: string }[] {
  const people = members.map((m) => ({ value: m.assignee, label: m.name }));
  const builders = members.filter((m) => m.kind === 'resident').map((m) => ({ value: `claude-code:${m.assignee.slice('resident:'.length)}`, label: `${m.name}'s Claude Code` }));
  return [...people, ...builders, { value: 'unknown', label: 'not known yet' }];
}

/** A template activity's holder in words: its member, or the old role it still holds by. */
export function holderWords(s: { assignee?: string | null; role?: string | null }, names: Names): string {
  if (s.assignee) return nameOf(names, s.assignee);
  return `by role: ${ROLE_WORDS[s.role ?? 'unknown'] ?? s.role} (choose a member)`;
}

/** A template's roles in words, as the editor offers them. */
export const ROLE_WORDS: Record<string, string> = {
  author: 'the task owner',
  witness: 'the witness',
  peer: 'the other resident',
  builder: "the owner's Claude Code",
  unknown: 'not known yet',
};

/** The types offered when an activity is written; whatever else a task holds stays as it is. */
export const TYPES = ['draft', 'review', 'implement', 'deliver', 'promote-to-house', 'merge', 'send', 'publish'];

export type LayerState = 'done' | 'open' | 'later';

export interface DrawnActivity {
  id: string;
  name: string;
  type: string;
  glyph: string;
  assignee: string;
  view: string;
  gated: boolean;
  slot: string | null;
}

export interface DrawnLayer {
  n: number;
  state: LayerState;
  label: string;
  acts: DrawnActivity[];
}

/**
 * A task's layers as the page draws them: numbered from 1, each done,
 * open or later, the one after the open layer saying what it waits for,
 * and each activity by its name, glyph, holder and state.
 */
export function drawLayers(layers: QueueActivity[][], open: number | null): DrawnLayer[] {
  return layers.map((layer, i) => {
    const state: LayerState = open === null || i < open ? 'done' : i === open ? 'open' : 'later';
    const label = state === 'done' ? 'done' : state === 'open' ? 'open now' : i === (open ?? -2) + 1 ? `opens when layer ${i} is done` : 'later';
    return {
      n: i + 1,
      state,
      label,
      acts: layer.map((a) => ({ id: a.act_id, name: actName(a), type: a.type, glyph: glyph(a.type), assignee: a.assignee, view: a.view, gated: a.gated, slot: a.slot })),
    };
  });
}

export interface TaskSummary {
  task: QueueTask;
  /** The layer open now, from 1, and how many there are. */
  at: number;
  of: number;
  /** What is in progress now: the open layer's activities not finished. */
  now: QueueCard[];
  /** The first blocked card in the open layer, naming its blocker. */
  blocked: QueueCard | null;
}

const FINISHED = new Set(['done', 'skipped']);

/**
 * The task list (lily's queue mocks, "Work · the task list"): each open
 * task with where it stands and what is in progress, in two sections:
 * Your move (a ready or active activity of the open layer is yours) and
 * Under way elsewhere.
 */
export function taskSummaries(tasks: QueueTask[], cards: QueueCard[], me: string | string[]): { mine: TaskSummary[]; others: TaskSummary[]; later: TaskSummary[] } {
  const holders = new Set(Array.isArray(me) ? me : [me]);
  const mine: TaskSummary[] = [];
  const others: TaskSummary[] = [];
  // Tasks where they hold something not yet theirs to do (a later layer, or blocked).
  const later: TaskSummary[] = [];
  for (const task of tasks) {
    if (task.status !== 'open') continue;
    const own = cards.filter((c) => c.task === task.number);
    const of = Math.max(task.open_layer === null ? 0 : task.open_layer + 1, ...own.map((c) => c.layer + 1));
    const now = task.open_layer === null ? [] : own.filter((c) => c.layer === task.open_layer && !FINISHED.has(c.view));
    const s: TaskSummary = { task, at: (task.open_layer ?? of - 1) + 1, of, now, blocked: now.find((c) => c.view === 'blocked') ?? null };
    if (now.some((c) => holders.has(c.assignee) && (c.view === 'ready' || c.view === 'active'))) mine.push(s);
    else {
      others.push(s);
      if (own.some((c) => holders.has(c.assignee) && !FINISHED.has(c.view))) later.push(s);
    }
  }
  return { mine, others, later };
}

/**
 * Whose queue a view shows (the witness, 2026-11-23: "a way to view each
 * household member's queue"): the member, and for a resident her Claude
 * Code too, whose work is hers.
 */
export function holdersOf(assignee: string): string[] {
  return assignee.startsWith('resident:') ? [assignee, `claude-code:${assignee.slice('resident:'.length)}`] : [assignee];
}

/** A blocked task's line: "Blocked on #12 Domain system rework · next: Draft the design, Lily". */
export function blockedLine(c: QueueCard, names: Names): string {
  if (!c.blocker) return `Blocked: ${c.reason ?? ''}`;
  const next = c.blocker.next ? `${actName(c.blocker.next)}, ${nameOf(names, c.blocker.next.assignee)}` : 'nothing open';
  return `Blocked on #${c.blocker.number} ${c.blocker.title} · next: ${next}`;
}

/** A citation's pin, if it has one: `lily:design/x.md@4e1c9a2` is pinned at 4e1c9a2. */
export const pinOf = (citation: string) => (citation.includes('@') ? citation.slice(citation.lastIndexOf('@') + 1) : null);
export const unpinned = (citation: string) => (citation.includes('@') ? citation.slice(0, citation.lastIndexOf('@')) : citation);

/** Where a citation's words are read: the house's repository, or a resident's library by her slug. */
export type Place = { house: true; slug: string; path: string } | { house: false; slug: string; path: string };

export function placeOf(citation: string): Place | null {
  const bare = unpinned(citation.trim());
  const house = /^house\/([a-z][a-z0-9-]*):(doc|thread)\/(.+)$/.exec(bare);
  if (house) return { house: true, slug: house[1], path: house[2] === 'thread' ? `threads/${house[3]}` : house[3] };
  const at = bare.indexOf(':');
  if (at <= 0 || bare.startsWith('slot:')) return null;
  return { house: false, slug: bare.slice(0, at), path: bare.slice(at + 1) };
}

/** A resident's file is cited with or without its `.md`; the library reads it with. */
export const withMd = (path: string) => (/\.[a-z0-9]+$/i.test(path.split('/').pop() ?? '') ? path : `${path}.md`);

/** A task's documents as its page lists them: each with its role, an unfilled slot saying "not yet". */
export function documentRows(docs: QueueDocument[]): { key: string; role: string; citation: string | null; shown: string; attached: boolean }[] {
  return docs.map((d) => ({ key: d.key, role: d.key.startsWith('slot:') && !d.citation ? d.key.slice(5) : d.role, citation: d.citation, shown: d.citation ?? 'not yet', attached: d.attached }));
}

/**
 * The roles a document can take on a task: each slot still empty (filling
 * it gives its activities this document to work on), then a source.
 */
export function roleChoices(docs: QueueDocument[]): { role: string; fills: boolean; label: string }[] {
  const empty = docs.filter((d) => d.key.startsWith('slot:') && !d.citation).map((d) => d.key.slice(5));
  return [...new Set(empty)].map((role) => ({ role, fills: true, label: `its ${role}` })).concat([{ role: 'source', fills: false, label: 'a source' }]);
}

/**
 * What adding (or removing) an activity does to the task's template
 * (sunna#90): the first change forks it for this task; a task already
 * forked runs its own copy; a task with no template has none to fork.
 */
export function forkNote(task: Pick<QueueTask, 'number' | 'template' | 'forked'>): string | null {
  if (!task.template) return null;
  if (task.forked) return `Task #${task.number} already runs its own copy, ${task.template} · #${task.number}; the change stays in it.`;
  return `Adding an activity forks ${task.template} for this task. Task #${task.number} then runs its own copy, named ${task.template} · #${task.number}; the template itself doesn't change.`;
}

/** "from the doc-to-pr template", or "forked from doc-to-pr" once its layers were edited. */
export const fromLine = (task: Pick<QueueTask, 'template' | 'forked'>) => (task.template ? (task.forked ? `forked from ${task.template}` : `from the ${task.template} template`) : 'written for this task');

export type PostKind = 'mine' | 'theirs' | 'platform';

/**
 * Whose a thread's post is, for its bubble: a platform or job line (a
 * review's decision is one, seshat#110) stands apart; a witness's is
 * yours unless it names another witness; a resident's is hers.
 */
export function postKind(meta: Record<string, string | undefined>, accountId?: string): PostKind {
  const kind = meta.by_kind;
  if (kind === 'platform' || kind === 'job') return 'platform';
  if (kind === 'witness') return accountId && meta.by_id && meta.by_id !== accountId ? 'theirs' : 'mine';
  return 'theirs';
}

/**
 * A task's whole arrangement after one change, as the layer edit takes
 * it (sunna#85): every activity by its id where it stands, the changed
 * one taken out and, unless it is removed (`to` null), put back at layer
 * `to` (0-based; past the last, a new layer) as `entry`. A layer left
 * empty goes.
 */
export function rearranged(layers: { act_id: string }[][], change: { id: string | null; to: number | null; entry: QueueEditEntry | null }): QueueEditEntry[][] {
  const from = change.id === null ? -1 : layers.findIndex((l) => l.some((a) => a.act_id === change.id));
  const out: QueueEditEntry[][] = layers.map((l, i) =>
    l.flatMap((a) => (a.act_id !== change.id ? [{ id: a.act_id }] : i === change.to && change.entry ? [change.entry] : [])),
  );
  if (change.to !== null && change.entry && change.to !== from) {
    if (change.to >= out.length) out.push([change.entry]);
    else out[change.to] = [...out[change.to], change.entry];
  }
  return out.filter((l) => l.length > 0);
}

/**
 * The holders that move with one (the witness, 2026-11-23: "the option to
 * change both assignees"): a resident's Claude Code is reached only
 * through her deliver in the layer before it (§3), so giving a Claude
 * Code activity to another resident's Claude Code gives that resident the
 * deliver before it, and giving a deliver to another resident gives her
 * Claude Code the activities after it. Pending ones only; started work
 * stays as it is.
 */
export function pairedHolders(layers: { act_id: string; type: string; assignee: string; status: string }[][], actId: string, assignee: string): { id: string; assignee: string }[] {
  const at = layers.findIndex((l) => l.some((a) => a.act_id === actId));
  if (at < 0) return [];
  const pending = (a: { status: string }) => a.status === 'pending';
  if (assignee.startsWith('claude-code:')) {
    const hers = `resident:${assignee.slice('claude-code:'.length)}`;
    return (layers[at - 1] ?? []).filter((a) => a.type === 'deliver' && pending(a) && a.assignee !== hers).map((a) => ({ id: a.act_id, assignee: hers }));
  }
  const self = layers[at].find((a) => a.act_id === actId);
  if (self?.type === 'deliver' && assignee.startsWith('resident:')) {
    const builder = `claude-code:${assignee.slice('resident:'.length)}`;
    return (layers[at + 1] ?? []).filter((a) => a.assignee.startsWith('claude-code:') && pending(a) && a.assignee !== builder).map((a) => ({ id: a.act_id, assignee: builder }));
  }
  return [];
}

/** An arrangement with the paired holders set on their entries. */
export function withPaired(arrangement: QueueEditEntry[][], pairs: { id: string; assignee: string }[]): QueueEditEntry[][] {
  const by = new Map(pairs.map((p) => [p.id, p.assignee]));
  return arrangement.map((l) => l.map((e) => ('id' in e && e.id && by.has(e.id) ? { ...e, assignee: by.get(e.id) as string } : e)));
}

/**
 * A task's document changed for another (the witness, 2026-11-23: a task
 * named her file where the document was the house's): every pending
 * activity working on it works on the new one instead; started work
 * keeps what it worked on. The arrangement for one layer edit, and how
 * many it changes.
 */
export function replacedDocument(layers: { act_id: string; artifact: string | null; status: string }[][], oldKey: string, citation: string): { arrangement: QueueEditEntry[][]; changed: number } {
  let changed = 0;
  const key = (c: string | null) => (c ?? '').split('@')[0].trim();
  const arrangement = layers.map((l) =>
    l.map((a) => {
      if (a.status === 'pending' && a.artifact && key(a.artifact) === oldKey) {
        changed += 1;
        return { id: a.act_id, artifact: citation } as QueueEditEntry;
      }
      return { id: a.act_id } as QueueEditEntry;
    }),
  );
  return { arrangement, changed };
}

/**
 * Where a card's step stands (the witness, 2026-11-23: "task cards should
 * show the current status of the current activity"): its view in words,
 * since when, and for a resident's step what her line is doing about it.
 */
export function stepStatus(c: Pick<QueueCard, 'view' | 'reason' | 'ready_at' | 'updated_at' | 'line' | 'type'>, now = Date.now()): string {
  const ago = (iso: string | null | undefined) => (iso ? ` ${since(iso, now)} ago` : '');
  switch (c.view) {
    case 'blocked':
      return `blocked${c.reason ? `: ${c.reason}` : ''}`;
    case 'failed':
      return `failed${c.reason ? `: ${c.reason}` : ''}`;
    case 'waiting':
      return 'waiting on an earlier layer';
    case 'active':
      if (c.line?.state === 'running') return `being worked, started${ago(c.line.since)}`;
      return `taken${ago(c.updated_at)}`;
    case 'ready': {
      const head = c.type === 'review' ? `ready for review${ago(c.ready_at)}` : `ready${ago(c.ready_at)}`;
      if (!c.line) return head;
      if (c.line.state === 'running') return `${head} · starting now`;
      if (c.line.state === 'busy') return `${head} · after ${c.line.other}`;
      return c.line.reason ? `${head} · line ${c.line.reason}` : head;
    }
    default:
      return c.view;
  }
}

/** Yesterday in the viewer's zone, as YYYY-MM-DD: a backfill runs through days before today. */
export function yesterday(now = new Date()): string {
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Every domain a resident's agreement declares, his and hers (2026-11-24): what a backfill names. */
export function declaredLists(agreement: { persons?: { witness: string | null; resident: string }; domains?: { person: string; domain: string }[] } | undefined): { his: string[]; hers: string[] } {
  const declared = agreement?.domains ?? [];
  const persons = agreement?.persons;
  const of = (person: string | null | undefined) => [...new Set(declared.filter((d) => person && d.person === person).map((d) => d.domain))].sort();
  return { his: of(persons?.witness), hers: of(persons?.resident) };
}

/** A resident's backfill in a line: where it runs, or none. */
export function backfillLine(s: { day: string; pass: string; turn: number; to: string } | null): string {
  if (!s) return 'no backfill running';
  return `running ${s.pass} for ${s.day}${s.turn > 1 ? ` (turn ${s.turn})` : ''}, through ${s.to}`;
}

