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

// ---- templates (sunna#83, #88) ----

/** The activity types a review must stand in front of (§6.1), as the server's `gated_types/0`. */
export const GATED = ['send', 'publish', 'spend', 'merge', 'promote-to-house'];

/** The roles a template's activity is held by, resolved to members when a task opens. */
export const ROLES = ['author', 'witness', 'peer', 'builder', 'unknown'] as const;

/** One activity of a template as the editor holds it. */
export interface TemplateSpec {
  type: string;
  role: string;
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
 * a gated activity needs an artifact slot and, in the layer directly
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
      if (!s.type.trim()) problems.push(`${at} needs a verb.`);
      if (GATED.includes(s.type)) {
        if (!s.artifact) problems.push(`${at} (${s.type}) needs an artifact slot.`);
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
