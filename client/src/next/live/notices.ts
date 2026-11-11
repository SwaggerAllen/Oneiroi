// What a change notice invalidates (apsu#24, client-state.md). Query
// keys are `['resident', id, area, ...]`; a notice names its stream, and
// the stream's prefix says which areas showed what changed. An unknown
// stream invalidates the resident's whole cache: over-fetching is safe,
// missing a change is not.

export interface Notice {
  kind: string | null;
  stream: string;
  ref: string | null;
  position: number;
}

export type Area = 'chat' | 'sessions' | 'memory' | 'records' | 'time' | 'soul' | 'bell' | 'settings';

const BY_PREFIX: Record<string, Area[]> = {
  conversation: ['chat', 'sessions'],
  reacts: ['chat'],
  memory: ['memory', 'chat', 'bell'],
  library: ['records', 'bell'],
  kinds: ['records', 'bell', 'settings'],
  routes: ['records', 'settings'],
  judgement: ['records'],
  ethos: ['records', 'soul'],
  audits: ['records'],
  journal: ['time'],
  schedule: ['time', 'sessions'],
  resident: ['soul', 'bell'],
  governance: ['soul', 'bell'],
  ledger: ['settings'],
  subscription: ['settings'],
  xenia: ['bell', 'settings'],
  asks: ['bell'],
  pieces: ['bell'],
  work: ['sessions', 'bell', 'settings'],
  plugins: ['soul', 'bell'],
};

/** The query-key prefixes a notice should invalidate for this resident. */
export function keysFor(residentId: string, notice: Notice): unknown[][] {
  const prefix = notice.stream.split('-')[0];
  const areas = BY_PREFIX[prefix];
  if (!areas) return [['resident', residentId]];
  return areas.map((area) => ['resident', residentId, area]);
}

/** Notices arrive once per projector that folded the event: keep the first. */
export function fresh(seen: Set<number>, notice: Notice): boolean {
  if (seen.has(notice.position)) return false;
  seen.add(notice.position);
  if (seen.size > 2000) seen.delete(seen.values().next().value as number);
  return true;
}
