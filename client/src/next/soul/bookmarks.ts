// Soul › Memory's pure parts: which bookmarks a view shows. Kept apart
// from the page to be tested.

import type { Bookmark, Tag } from '../../api/types';

export type MemoryView = 'index' | 'all' | 'pinned' | 'use';

/** The numbers the index lists, as bookmarks, in its order; a number not at hand is skipped. */
export function listedBookmarks(listed: number[], all: Bookmark[]): Bookmark[] {
  const byNumber = new Map(all.map((b) => [b.number, b]));
  return listed.flatMap((n) => byNumber.get(n) ?? []);
}

/** The tags a bookmark list can be filtered by: the active ones, as the old Memory's tabs were. */
export const activeTags = (tags: Tag[]) => tags.filter((t) => t.state === 'active').map((t) => t.slug);

/** A tag and a search, both optional, over the line and the summary. */
export function filterBookmarks(rows: Bookmark[], tag: string | null, query: string): Bookmark[] {
  const needle = query.trim().toLowerCase();
  return rows.filter(
    (b) =>
      (tag === null || b.tags.includes(tag)) &&
      (!needle || b.line.toLowerCase().includes(needle) || (b.summary ?? '').toLowerCase().includes(needle)),
  );
}

/** "one turn" or "3 turns". */
export const spanWords = (turnsBack: number) => (turnsBack === 1 ? 'one turn' : `${turnsBack} turns`);

/** Who an actor is, in the witness's words. */
export const who = (kind: string | undefined | null, name: string) =>
  kind === 'witness' ? 'you' : kind === 'resident' ? name : (kind ?? 'unknown');
