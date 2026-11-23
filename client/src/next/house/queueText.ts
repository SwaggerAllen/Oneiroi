import type { QueueCard } from '../../api/types';

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
