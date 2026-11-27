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

export type Area = 'chat' | 'sessions' | 'memory' | 'records' | 'time' | 'soul' | 'bell' | 'settings' | 'threads' | 'succession' | 'capture-failures';

const BY_PREFIX: Record<string, Area[]> = {
  conversation: ['chat', 'sessions', 'capture-failures'],
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
  // Her own threads (seshat#106): a thread written reads its sheet again.
  threads: ['threads'],
  // Her succession (janus): every page of it reads again (the witness,
  // 2026-11-26: pages are pushed to, not polled).
  succession: ['succession'],
};

/**
 * How often a page whose changes arrive as notices reads anyway: only for
 * a socket that dropped or a reader the channel does not reach. Pages are
 * pushed to, not polled (CLAUDE.md); this is the fallback, never the way.
 */
export const PUSHED_FALLBACK_MS = 5 * 60_000;

/** The document screen's context (its threads' counts, its tasks, its review), house-wide. */
export const DOC_CONTEXT = ['household', 'queue', 'context'];

/**
 * The query-key prefixes a notice should invalidate for this resident.
 * The bell's own list is pushed by the server (brain#94), never read
 * again for a notice: the bell area invalidates only what waits on her.
 */
export function keysFor(residentId: string, notice: Notice): unknown[][] {
  const prefix = notice.stream.split('-')[0];
  const areas = BY_PREFIX[prefix];
  if (!areas) return [['resident', residentId]];
  const keys = areas.map((area) => (area === 'bell' ? ['resident', residentId, 'bell', 'hers'] : ['resident', residentId, area]));
  // A thread of hers on a document changes what its document screen says.
  if (prefix === 'threads') return [...keys, DOC_CONTEXT];
  // A conversation written changes the unread counts across her house.
  if (prefix === 'conversation') return [...keys, ['unread']];
  return keys;
}

/**
 * What a household notice reads again (sunna#80, seshat#109): a queue
 * change, the queue's queries (the document screens' contexts among
 * them); a thread written, the house's reads and the unread counts.
 */
export function houseKeys(notice: Notice): unknown[][] {
  if (notice.stream.startsWith('threads')) return [['household'], ['unread']];
  // The charter, members and beats; the rounds (2026-11-26).
  if (notice.stream.startsWith('household')) return [['household']];
  if (notice.stream.startsWith('rounds')) return [['household', 'beats'], ['household', 'activity']];
  return [['household', 'queue']];
}

/** Notices arrive once per projector that folded the event: keep the first. */
export function fresh(seen: Set<number>, notice: Notice): boolean {
  if (seen.has(notice.position)) return false;
  seen.add(notice.position);
  if (seen.size > 2000) seen.delete(seen.values().next().value as number);
  return true;
}
