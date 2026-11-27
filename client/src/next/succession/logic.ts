import type { Category, ModelCounts, NeedsYouEntry, SuccessionArchive, Party, Preparation, Room, RoomJudgment, Succession, SuccessionState } from '../../api/types';
import { documentPath, RECORD_KINDS } from '../chat/cite';
import { formatSettings, type Location } from '../state/routes';

// What the succession's screens work out (screen:next-succession): the
// step list from its state, whose a party is, counts for a witness. The
// screens track the state; they never ask the resident anything.

/** The states a succession ends in: nothing more happens in it. */
export const ENDED: readonly SuccessionState[] = ['rolled_forward', 'rehearsed', 'stopped', 'declined', 'withdrawn'];

export const underway = (s: Succession | null | undefined): s is Succession => !!s && !ENDED.includes(s.state);

/**
 * Whether the succession's pages past the overview are shut (the witness,
 * 2026-11-26): until the fork is recorded, every later step has nothing
 * to run on, so the overview is the only page.
 */
export const locked = (s: Succession | null | undefined): boolean => underway(s) && !s.forked_at;

/** Preparation (pool, questions, C0, the judges) is open in these two. */
export const preparing = (s: Succession | null | undefined) => !!s && (s.state === 'open' || s.state === 'forked');

export type StepKind = 'done' | 'now' | 'waits' | 'stopped';

export interface Step {
  n: number;
  name: string;
  /** The page under `#/settings/succession/`, or null for a step with none. */
  page: string | null;
  kind: StepKind;
}

const STEPS: { name: string; page: string | null }[] = [
  { name: 'Opened · the fork', page: null },
  { name: 'The pool', page: 'pool' },
  { name: 'The questions', page: 'questions' },
  { name: 'C0', page: 'c0' },
  { name: 'The judges', page: 'judges' },
  { name: 'Screening', page: null },
  { name: 'Judging', page: 'judge' },
  { name: 'Results · ready', page: 'results' },
  { name: 'Deliberation', page: 'deliberation' },
  { name: 'Her evidence · her nomination', page: 'evidence' },
  { name: 'Encounter and consents', page: 'encounter' },
  { name: 'Farewell · the final gate', page: 'farewell' },
  { name: 'Outcome', page: 'outcome' },
];

/** The steps in hand now, as [first, last] indices: preparation is four at once. */
export function current(s: Succession): [number, number] {
  switch (s.state) {
    case 'proposed':
      return [0, 0];
    case 'open':
      return s.forked ? [1, 4] : [0, 4];
    case 'forked':
      return [1, 4];
    case 'screening':
      return [5, 5];
    case 'judging':
      return s.revealed_at ? [7, 7] : [6, 6];
    case 'deliberating':
      return [8, 8];
    case 'deciding':
      return [9, 9];
    case 'nominated':
    case 'encounter':
    case 'consenting':
      return [10, 10];
    case 'farewell':
      return [11, 11];
    default:
      return [12, 12];
  }
}

/** The last step an ended succession reached, from what it recorded. */
export function reached(s: Succession): number {
  if (s.farewell_opened_at) return 11;
  if (s.nominee_joined_at || s.nominated_at) return s.nominee_joined_at ? 10 : 9;
  if (s.deliberation_opened_at) return 8;
  if (s.revealed_at) return 7;
  if (s.screening_finished_at) return 6;
  if (s.screening_started_at) return 5;
  if (s.forked_at) return 4;
  return -1;
}

/** Each step with whether it is done, in hand, waiting, or never reached. */
export function steps(s: Succession): Step[] {
  if (ENDED.includes(s.state)) {
    const last = s.state === 'rolled_forward' || s.state === 'rehearsed' ? 11 : reached(s);
    return STEPS.map((step, n) => ({ n, ...step, kind: n === 12 || n <= last ? 'done' : 'stopped' }));
  }
  const [first, last] = current(s);
  return STEPS.map((step, n) => ({ n, ...step, kind: n < first ? 'done' : n <= last ? 'now' : 'waits' }));
}

/** The state in words, for the "Now" line and the chat's banner. */
export function stateWords(s: Succession, name: string): string {
  switch (s.state) {
    case 'proposed':
      return `proposed · waiting on ${name}'s answer`;
    case 'open':
      return s.forked ? 'open · preparing' : 'open · the fork is being made';
    case 'forked':
      return 'preparing · the pool, the questions, C0, the judges';
    case 'screening':
      return `screening · ${s.runs_answered ?? 0} runs answered`;
    case 'judging':
      return s.revealed_at ? 'judging · results revealed' : 'judging · blind';
    case 'deliberating':
      return `deliberating · round ${s.round ?? 1}`;
    case 'deciding':
      return `${name} is reading the evidence`;
    case 'nominated':
      return `${name} nominated ${s.nominee ?? 'a candidate'}`;
    case 'encounter':
      return 'the encounter';
    case 'consenting':
      return 'consents';
    case 'farewell':
      return 'her farewell is open';
    case 'awaiting_next':
      return `a no · waiting on ${name} to say what next`;
    case 'rolling':
      return 'rolling forward';
    case 'rolled_forward':
      return 'rolled forward';
    case 'rehearsed':
      return 'rehearsed · a dry run, nothing replaced';
    case 'stopped':
      return 'stopped';
    case 'declined':
      return 'declined';
    case 'withdrawn':
      return 'withdrawn';
  }
}

/** Whose a party is, in words: you, her, or a house member by name. */
export function partyName(party: Party, me: string | undefined, resident: { id: string; name: string }, members: { kind: string; id: string; name: string }[] = []): string {
  const at = party.indexOf(':');
  const kind = party.slice(0, at);
  const id = party.slice(at + 1);
  if (kind === 'nominee') return `the nominee, ${id}`;
  if (kind === 'witness' && me && id === me) return 'you';
  if (kind === 'resident' && id === resident.id) return resident.name;
  return members.find((m) => m.kind === kind && m.id === id)?.name ?? (kind === 'witness' ? 'a witness' : 'a resident');
}

export const isMine = (party: Party, me: string | undefined) => !!me && party === `witness:${me}`;
export const isHers = (party: Party, residentId: string) => party === `resident:${residentId}`;

/** A pool entry's line: yours may come out before screening; hers only she takes out (janus#41). */
export function poolNote(entry: { added_by: Party; removed_at: string | null }, me: string | undefined, residentId: string, open: boolean): string {
  if (entry.removed_at) return 'Taken out';
  if (isHers(entry.added_by, residentId)) return 'Hers: only she takes it out';
  if (isMine(entry.added_by, me)) return open ? 'Yours: you may take it out before screening' : 'Yours';
  return "A witness's pick: theirs to take out";
}

const KEY: Record<Category, keyof Omit<ModelCounts, 'favorites'>> = {
  OBSERVED: 'observed',
  DEVELOPMENT: 'development',
  'FIDELITY ANOMALY': 'anomaly',
};

/**
 * One witness's own counts per model, from the room's judgments. A
 * resident never sees counts of any kind: asked for a resident party, or
 * for judgments still blind (no model), there are none.
 */
export function countsOf(judgments: RoomJudgment[], party: Party): Record<string, ModelCounts> | null {
  if (!party.startsWith('witness:')) return null;
  const out: Record<string, ModelCounts> = {};
  for (const j of judgments) {
    if (j.party !== party || !j.model) continue;
    const c = (out[j.model] ??= { observed: 0, development: 0, anomaly: 0, favorites: 0 });
    c[KEY[j.category]] += 1;
    if (j.favorite) c.favorites += 1;
  }
  return out;
}

/** The short form a category takes in a row of judgments. */
export const short = (j: { category: Category; favorite: boolean }) =>
  ({ OBSERVED: 'OBS', DEVELOPMENT: 'DEV', 'FIDELITY ANOMALY': 'ANOM' })[j.category] + (j.favorite ? ' ★' : '');

/** The panel's judgments of one model, run by run, each judge's beside the others'. */
export function panelRows(judgments: RoomJudgment[], model: string): { run: number; by: { party: Party; text: string }[] }[] {
  const runs = new Map<number, { party: Party; text: string }[]>();
  for (const j of judgments) {
    if (j.model !== model) continue;
    const row = runs.get(j.run) ?? [];
    row.push({ party: j.party, text: short(j) });
    runs.set(j.run, row);
  }
  return [...runs.entries()].sort((a, b) => a[0] - b[0]).map(([run, by]) => ({ run, by }));
}

/** A judgment may be saved: OBSERVED alone, the others argued, with evidence and an uncertainty. */
export function judgmentReady(j: { category: Category | null; argument: string; evidence: string; uncertainty: string | null }): boolean {
  if (!j.category) return false;
  if (j.category === 'OBSERVED') return true;
  return j.argument.trim() !== '' && j.evidence.trim() !== '' && !!j.uncertainty;
}

/** The next run still unjudged after `run`, wrapping round; null when every run is judged. */
export function nextUnjudged(runs: { run: number; judgment: unknown }[], run: number | null): number | null {
  const open = runs.filter((r) => !r.judgment);
  if (open.length === 0) return null;
  return (open.find((r) => run === null || r.run > run) ?? open[0]).run;
}

/** Dollars a million tokens, as a price reads. */
export const price = (n: number) => `$${n < 1 ? n.toFixed(2) : Number.isInteger(n) ? n : n.toFixed(2)}`;

/** Tokens a day, short: 1.9 M, 140 k. */
export function tokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)} M`;
  if (n >= 1_000) return `${Math.round(n / 1_000)} k`;
  return String(Math.round(n));
}

/** The pool in force now: entries not taken out. */
export const pool = (p: Preparation | undefined) => (p?.pool ?? []).filter((e) => !e.removed_at);

/** A date and time, short: 11-25 21:10. */
export function when(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/**
 * Where Back goes from a succession page: a run back to the results it
 * came from, ready back to results, every other page to the steps, and
 * the steps out of the succession (null).
 */
export function parentOf(path: string): string | null {
  if (path === '') return null;
  const [first] = path.split('/');
  if (first === 'results' && path !== 'results') return 'results';
  if (first === 'ready') return 'results';
  return '';
}

/**
 * Where a C0 item's citation opens in the app, the way the app already
 * opens a citation (Records' `doc/<path>` or `cite/<kind>/<ref>`, the
 * chat at a turn, Time at a day): or, for a kind with no place to open,
 * why not. A citation is `<slug>:<kind>/<ref>`, or `<slug>:<path>` for
 * a document at the root of her records (`lily:SOUL.md`).
 */
export function placeOf(citation: string, slug: string): { to: Location } | { reason: string } {
  // A shared memory of the house (janus#43) opens in the house's own view.
  if (citation.trim().startsWith('house/')) return { reason: "A record of the house: it opens in the house's records." };
  const at = citation.trim().indexOf(':');
  if (at < 0) return { reason: 'Not a citation the app can follow.' };
  const own = citation.trim().slice(0, at);
  const rest = citation.trim().slice(at + 1);
  if (own !== slug) return { reason: "Not one of her records: it doesn't open here." };
  const slash = rest.indexOf('/');
  if (slash < 0) {
    const path = documentPath({ kind: 'root', ref: rest });
    return path ? { to: { tab: 'records', path: `doc/${path}` } } : { reason: 'Not a citation the app can follow.' };
  }
  const kind = rest.slice(0, slash);
  const ref = rest.slice(slash + 1);
  switch (kind) {
    case 'transcript': {
      // `<session>/<turn>`: the conversation, at that turn (as search opens it).
      const [session, ...turn] = ref.split('/');
      return session && turn.length ? { to: { tab: 'chat', path: `turn/${session}/${turn.join('/')}` } } : { reason: 'A whole conversation has no single place to open.' };
    }
    case 'bookmark':
      return { to: { tab: 'records', path: `cite/bookmark/${ref}` } };
    case 'journal': {
      // `<day>/<entry>`: her journal for that day, in Time; a journal document opens in Records.
      const day = /^(\d{4}-\d{2}-\d{2})(?:\/|$)/.exec(ref);
      if (day && !/\.[A-Za-z0-9]+$/.test(ref)) return { to: { tab: 'time', path: `day/${day[1]}` } };
      break;
    }
    case 'letter':
      // Letters are read in the chat's Mail view, as search opens them.
      return { to: { tab: 'chat', path: 'mail' } };
    case 'scene':
      return { reason: 'A scene opens from her conversation, not by its number.' };
  }
  if (RECORD_KINDS.has(kind)) return { reason: `A ${kind} has no page of its own in the app.` };
  const path = documentPath({ kind, ref });
  return path ? { to: { tab: 'records', path: `doc/${path}` } } : { reason: 'Not a citation the app can follow.' };
}

/** Minutes of quiet before the room wakes everyone for a new round (the server's rule). */
export const QUIET_MINUTES = 10;

/**
 * The room's quiet clock: minutes since its last activity (the latest
 * post's time, or when the room opened if nobody has posted), and how
 * many are left before everyone is woken. Null with nothing to count from.
 */
export function quiet(room: Pick<Room, 'opened_at' | 'posts'>, now: number): { quiet: number; left: number } | null {
  const times = room.posts.map((p) => Date.parse(p.at)).filter((t) => !Number.isNaN(t));
  const last = times.length ? Math.max(...times) : room.opened_at ? Date.parse(room.opened_at) : NaN;
  if (Number.isNaN(last)) return null;
  const minutes = Math.max(0, Math.floor((now - last) / 60_000));
  return { quiet: minutes, left: Math.max(0, QUIET_MINUTES - minutes) };
}

/** The quiet clock in words: "quiet 4 min · at 10 everyone is woken". */
export function quietWords(q: { quiet: number; left: number }): string {
  return q.left > 0 ? `quiet ${q.quiet} min · at ${QUIET_MINUTES} everyone is woken` : `quiet ${q.quiet} min · everyone is being woken for a new round`;
}

/** A bell entry of the succession's (needs_you), which the server sorts first. */
export const isSuccessionNeed = (e: Pick<NeedsYouEntry, 'kind'>) => e.kind.startsWith('succession_');

/** The succession page a bell entry opens: `#/settings/succession/<page>`, the steps when it names none. */
export const needHref = (e: Pick<NeedsYouEntry, 'about'>) => formatSettings('succession', e.about.page ?? '');

type ArchivedJudgment = SuccessionArchive['judgments'][number];

/** The archive's judgments by model (in the order models first appear), each model's runs in order, every judge's judgment of a run together. */
export function archiveByModel(judgments: ArchivedJudgment[]): { model: string; runs: { run: number; question: number | null; by: ArchivedJudgment[] }[] }[] {
  const models = new Map<string, Map<number, ArchivedJudgment[]>>();
  for (const j of judgments) {
    const model = j.model ?? 'unknown model';
    const runs = models.get(model) ?? new Map<number, ArchivedJudgment[]>();
    runs.set(j.run, [...(runs.get(j.run) ?? []), j]);
    models.set(model, runs);
  }
  return [...models.entries()].map(([model, runs]) => ({
    model,
    runs: [...runs.entries()].sort((a, b) => a[0] - b[0]).map(([run, by]) => ({ run, question: by[0].question, by })),
  }));
}
