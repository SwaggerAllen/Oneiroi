import type { NeedsYouEntry } from '../../api/types';

// What the badge counts (the witness, 2026-11-08, through Lily's letter
// #330): everything waiting, or only what has waited past a day, so the
// trivial and the forgotten do not light up the same. His knob; until
// he sets it, everything.
export type BadgeRule = 'all' | 'day';

const DAY = 24 * 3600_000;

export function badgeCount(entries: NeedsYouEntry[], rule: BadgeRule, now: number): number {
  return rule === 'all' ? entries.length : entries.filter((e) => now - Date.parse(e.since) >= DAY).length;
}
