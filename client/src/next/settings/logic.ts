// The settings pages' logic, apart from their components (screens/next-settings.md).
import { RequestFailed } from '../../api/client';
import type { BudgetLine, KindEntry, ProfileEntry, RegressionCard, RegressionRun, RegressionRunDetail, RouteEntry, RoutesData, WorkQueue } from '../../api/types';
import { sortCards } from './deck';

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

const dollars = (nano: number) => `$${(nano / 1e9).toFixed(2)}`;

/** A span in the largest two units that say it: "45m", "2h 10m", "3d 4h"; under a minute is "under a minute". */
export function span(seconds: number): string {
  const m = Math.floor(seconds / 60);
  if (m < 1) return 'under a minute';
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return m % 60 ? `${h}h ${m % 60}m` : `${h}h`;
  return h % 24 ? `${Math.floor(h / 24)}d ${h % 24}h` : `${Math.floor(h / 24)}d`;
}

// A run past this is marked for a look (sunna#58): a guess, not a
// measure; the loop itself ends a run only once it is stale (sunna#37).
export const LONG_RUN_SECONDS = 60 * 60;

/** The running activity's run so far, in seconds, or null when nothing runs. */
export function runSeconds(q: Pick<WorkQueue, 'running_act' | 'running_since'>, nowMs: number): number | null {
  if (!q.running_act || !q.running_since) return null;
  return Math.max(0, Math.floor((nowMs - Date.parse(q.running_since)) / 1000));
}

/**
 * The line in one line (sunna#86): the house queue activity it runs and
 * for how long, or why it rests; the day's runs and the work budget. The
 * old queue's items and its arming are retired (sunna#102).
 */
export function loopLine(name: string, q: WorkQueue, nowMs: number = Date.now()): string {
  const cap = q.budget ? `${dollars(q.budget.left)} left of ${dollars(q.budget.cap)} a ${q.budget.period}` : 'no cap';
  const runs = `${q.runs_today} of ${q.runs_a_day} runs today; work budget: ${cap}.`;
  if (q.running_act) {
    const run = runSeconds(q, nowMs);
    return `Running activity ${q.running_act} of task #${q.running_task}${run === null ? '' : `, for ${span(run)}`}. ${runs}`;
  }
  if (q.rested) return `Resting: ${q.rested}. ${runs}`;
  return `${name}'s line has not run yet. ${runs}`;
}

/**
 * The one command that sets a resident up on a Mac (dioscuri#8): the
 * same for any resident and either setup, her slug and id in it and
 * never a token, which the script asks for. Single-quoted where a value
 * came from a person, so a shell reads it as written.
 */
export function setupCommand(origin: string, kind: 'writer' | 'reader', slug: string, residentId: string, extra: { substack?: string; email?: string } = {}): string {
  const q = (v: string) => `'${v.replace(/'/g, `'\\''`)}'`;
  const parts = [`bash <(curl -fsSL ${origin.replace(/\/$/, '')}/setup.sh)`, kind, '--slug', slug, '--resident', residentId];
  if (kind === 'reader' && extra.substack?.trim()) parts.push('--substack', q(extra.substack.trim()));
  if (kind === 'reader' && extra.email?.trim()) parts.push('--email', q(extra.email.trim()));
  return parts.join(' ');
}
