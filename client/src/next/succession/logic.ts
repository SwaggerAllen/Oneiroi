import type { Category, ModelCounts, Party, Preparation, RoomJudgment, Succession, SuccessionState } from '../../api/types';

// What the succession's screens work out (screen:next-succession): the
// step list from its state, whose a party is, counts for a witness. The
// screens track the state; they never ask the resident anything.

/** The states a succession ends in: nothing more happens in it. */
export const ENDED: readonly SuccessionState[] = ['rolled_forward', 'rehearsed', 'stopped', 'declined', 'withdrawn'];

export const underway = (s: Succession | null | undefined): s is Succession => !!s && !ENDED.includes(s.state);

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

/** A pool entry's line: yours may come out before screening; hers nobody removes. */
export function poolNote(entry: { added_by: Party; removed_at: string | null }, me: string | undefined, residentId: string, open: boolean): string {
  if (entry.removed_at) return 'Taken out';
  if (isHers(entry.added_by, residentId)) return 'Hers: nobody removes it';
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
