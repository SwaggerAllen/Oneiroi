// Soul's pure parts: which page the stack's top names, and the small
// readings the pages share. Kept apart from the components to be tested.

import type { Switch } from '../../api/client';
import type { PluginEntry, PluginProposal, Tag } from '../../api/types';

export const IDENTITY = ['SOUL.md', 'IDENTITY.md', 'USER.md', 'GOALS.md', 'LINKS.md'] as const;

export const PAGES = [
  'agreement',
  'plugins',
  'soul-lines',
  'habits',
  'seeds',
  'commitments',
  'positions',
  'predictions',
  'letters',
  'tags',
  'revisions',
  'proposals',
] as const;
export type Page = (typeof PAGES)[number];

/** The stack's top as a page: the root, a named page, or an edit of one identity file. */
export function soulPage(path: string): { page: 'root' } | { page: Page } | { page: 'edit'; file: string } {
  if (path.startsWith('edit/')) {
    const file = path.slice(5);
    return (IDENTITY as readonly string[]).includes(file) ? { page: 'edit', file } : { page: 'root' };
  }
  return (PAGES as readonly string[]).includes(path) ? { page: path as Page } : { page: 'root' };
}

export const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString() : '');

/** The switches a drafted version would move, against the values now. */
export function switchChanges(switches: Switch[], draft: Record<string, boolean>): Switch[] {
  return switches.filter((s) => draft[s.key] !== undefined && draft[s.key] !== s.value);
}

/** Her tag proposals still waiting on the witness. */
export const proposedTags = (tags: Tag[]) => tags.filter((t) => t.state === 'proposed' && t.proposed_by?.kind !== 'witness');

/** "3 right · 1 wrong · 0 void". */
export function tallyLine(tally: Partial<Record<'right' | 'wrong' | 'void', number>>): string {
  return (['right', 'wrong', 'void'] as const).map((k) => `${tally[k] ?? 0} ${k}`).join(' · ');
}

export type PluginAction = { kind: 'propose'; change: PluginProposal['change']; label: string } | { kind: 'off'; label: string };

/**
 * What the witness may do with a plugin (brain#68, agathos-daimon#37):
 * an installable plugin switches off at either word; everything else is
 * a proposal she answers. Nothing while a proposal on it is open.
 */
export function pluginActions(p: PluginEntry, open: boolean): PluginAction[] {
  if (open) return [];
  const out: PluginAction[] = [];
  if (!p.installed) out.push({ kind: 'propose', change: 'install', label: 'Propose install' });
  if (p.installed && !p.on) out.push({ kind: 'propose', change: 'on', label: 'Propose on' });
  if (p.on && p.tier === 'installable') out.push({ kind: 'off', label: 'Switch off' });
  if (p.on && p.tier === 'first_party') out.push({ kind: 'propose', change: 'off', label: 'Propose off' });
  if (p.installed) out.push({ kind: 'propose', change: 'remove', label: 'Propose removal' });
  return out;
}

// What a revision may name (kumbukumbu's target kinds).
export const REVISION_TARGETS = ['bookmark', 'conversation', 'turn', 'position', 'prediction', 'date', 'figure', 'document', 'journal', 'habit', 'seed'] as const;
