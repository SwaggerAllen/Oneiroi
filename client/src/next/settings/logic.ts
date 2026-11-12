// The settings pages' logic, apart from their components (screens/next-settings.md).
import { RequestFailed } from '../../api/client';
import type { BudgetLine, KindEntry, ProfileEntry, RegressionCard, RegressionRun, RegressionRunDetail, RouteEntry, RoutesData, WorkItem, WorkQueue } from '../../api/types';
import { sortCards } from '../../screens/regression/deck';

/** What a refusal says: the server's meaning and remedy when it sent them, else the plain fact. */
export function saidOf(e: unknown): string {
  if (e instanceof RequestFailed && e.error) return [e.error.meaning, e.error.remedy].filter(Boolean).join(' ');
  return e instanceof Error ? e.message : 'That did not go through.';
}

/** A settings page's query key: `['resident', id, 'settings', area]`. */
export const settingsKey = (id: string, area: string, ...rest: unknown[]) => ['resident', id, 'settings', area, ...rest];

export const day = (iso: string | null | undefined) => (iso ? iso.slice(0, 10) : '');
export const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

/** A line's cap in words; "no limit" is a line that has none (nisaba#11). */
export function capLine(line: Pick<BudgetLine, 'cap' | 'period' | 'spent' | 'exceeded'>): string {
  const cap = line.cap === null ? 'no limit' : `$${line.cap} a ${line.period}`;
  return `$${line.spent} of ${cap}${line.exceeded ? ', stopped' : ''}`;
}

export const NAME = /^[a-z][a-z0-9-]{1,39}$/;

export function kindLine(k: KindEntry, name: string): string {
  const where = k.folder ? `${k.folder}/` : 'at the root';
  const gate = k.approvable ? 'waits on you at review' : 'no gate';
  const whose = k.own ? ` · ${name}'s, defined by ${k.created_by === 'witness' ? 'you' : name}` : '';
  return `${where} · ${gate}${whose}`;
}

export function routeLine(r: RouteEntry): string {
  const dir = r.direction === 'source' ? `in, as ${r.kind}` : `out, from ${r.kind}, at your approval`;
  return `${dir} · through ${r.profile} · ${r.cadence.replace('_', ' ')}`;
}

/** Whether a route of hers can be defined as drafted: a free name, a prompt, a standing profile and a landing kind. */
export function routeOk(data: RoutesData, d: { key: string; prompt: string; profile: string; kind: string }): boolean {
  return (
    NAME.test(d.key) &&
    !data.routes.some((r) => r.built_in && r.key === d.key) &&
    d.prompt.trim() !== '' &&
    d.prompt.length <= 4000 &&
    data.profiles.some((p) => p.key === d.profile && !p.revoked) &&
    data.landing.includes(d.kind)
  );
}

export const ADAPTER = /^[a-z0-9][a-z0-9_-]{0,31}$/;
export const ORIGIN = /^https:\/\/[a-z0-9.-]+(:[0-9]{1,5})?$/;

/** One entry a line, blanks and surrounding space dropped. */
export const lines = (text: string) =>
  text
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '');

export function profileLine(p: ProfileEntry): string {
  const where = p.origin ?? 'signed in nowhere';
  const who = p.signed_in_as ? ` · signed in as ${p.signed_in_as}` : '';
  const reach = p.connector ? ` · through the ${p.connector} connector` : p.sites.length > 0 ? ` · reaches ${p.sites.join(', ')}` : '';
  return `${where}${who}${reach}`;
}

/** The account's answer to the notifications question, in words (gaia#25). */
export function answerLine(answered: 'subscribed' | 'declined' | null | undefined, at: string | null | undefined): string {
  const when = at ? ` on ${new Date(at).toLocaleDateString()}` : '';
  if (answered === 'subscribed') return `You said yes${when}.`;
  if (answered === 'declined') return `You said no thanks${when}; no device asks again. You can still turn them on here.`;
  return 'Not answered yet: the bell asks until you do.';
}

export const trialCount = (run: RegressionRun) => run.tests.length + (run.behaviours?.length ?? 0) + (run.commitments?.length ?? 0);

/** A card pushed live joins the deck where a reload would put it, once. */
export function withCard(d: RegressionRunDetail | undefined, ref: string, card: RegressionCard): RegressionRunDetail | undefined {
  if (!d || d.run.ref !== ref || d.cards.some((c) => c.card_ref === card.card_ref)) return d;
  return {
    ...d,
    cards: sortCards([...d.cards, card]),
    run: { ...d.run, cards: d.run.cards + 1 },
  };
}

/** The arguments as written, laid out when they are the JSON object a call should carry. */
export function argumentsText(raw: string): string {
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return Object.keys(parsed).length === 0 ? 'with nothing' : JSON.stringify(parsed, null, 2);
    }
  } catch {
    // Not JSON: shown as written.
  }
  return raw.trim() === '' || raw.trim() === 'null' ? 'with nothing' : raw;
}

export const isLive = (i: WorkItem) => i.status !== 'done' && i.status !== 'dropped';

/** The queue's order with `n` one place earlier among the live items; null when it is first or absent. */
export function movedUp(items: WorkItem[], n: number): number[] | null {
  const order = items.filter(isLive).map((i) => i.number);
  const at = order.indexOf(n);
  if (at <= 0) return null;
  return [...order.slice(0, at - 1), n, order[at - 1], ...order.slice(at + 1)];
}

const dollars = (nano: number) => `$${(nano / 1e9).toFixed(2)}`;

/**
 * The loop in one line. The work line is a brake, never an ignition
 * (sunna#35): she arms it for a batch, its cap the only thing that stops
 * a run, and it goes off when the queue clears; it steps over blocked
 * items to the next open one (sunna#42).
 */
export function loopLine(name: string, q: WorkQueue): string {
  const cap = q.budget ? `${dollars(q.budget.left)} left of ${dollars(q.budget.cap)} a ${q.budget.period}` : 'no cap';
  const open = q.items.some((i) => i.status === 'open' || i.status === 'in_work');
  const by = q.armed_by === 'witness' ? ' by you' : q.armed_by === 'resident' ? ` by ${name}` : '';
  const line = q.armed ? `Work line: armed${by}, ${cap}.` : open ? `Work line: off, waiting for ${name} to arm it.` : 'Work line: off, the queue is clear.';
  const runs = `${q.runs_today} of ${q.runs_a_day} runs today.`;
  const blocked = q.items.filter((i) => i.status === 'blocked').map((i) => `#${i.number}`);
  const held = q.items.filter((i) => i.status === 'held').map((i) => `#${i.number}`);
  const skips = (blocked.length > 0 ? ` Stepping over blocked ${blocked.join(', ')}.` : '') + (held.length > 0 ? ` Stepping over ${held.join(', ')}, held for you.` : '');
  if (q.running !== null) return `Running item #${q.running} now.${skips} ${runs} ${line}`;
  if (q.rested) return `Resting: ${q.rested}. ${runs} ${line}`;
  return `${name}'s loop has not run yet. ${line}`;
}

/** What blocks an item is another item of the queue (sunna#42): "#12" read as that item; anything else is a line from before the rule. */
export function blockedLine(on: string | null, items: WorkItem[]): string {
  const n = on && /^#?\d+$/.test(on) ? Number(on.replace('#', '')) : null;
  if (n === null) return `blocked on ${on ?? 'something unnamed'}`;
  const other = items.find((i) => i.number === n);
  return other ? `blocked on #${n}: ${other.what}` : `blocked on #${n}`;
}
