import { describe, expect, it } from 'vitest';
import type { Switch } from '../../api/client';
import type { PluginEntry, Tag } from '../../api/types';
import { pluginActions, proposedTags, soulPage, switchChanges, tallyLine } from './soul';

const plugin = (p: Partial<PluginEntry>): PluginEntry => ({
  key: 'k',
  name: 'K',
  about: '',
  tier: 'first_party',
  place: 'prefix',
  reads: [],
  installed: true,
  on: true,
  carried_over: false,
  changed_by: null,
  changed_at: null,
  ...p,
});

describe('soul', () => {
  it('reads the stack top as a page', () => {
    expect(soulPage('')).toEqual({ page: 'root' });
    expect(soulPage('habits')).toEqual({ page: 'habits' });
    expect(soulPage('edit/SOUL.md')).toEqual({ page: 'edit', file: 'SOUL.md' });
    // Only the identity files are proposed from here; anything else is the root.
    expect(soulPage('edit/AGENTS.md')).toEqual({ page: 'root' });
    expect(soulPage('nowhere')).toEqual({ page: 'root' });
  });

  it('names the switches a drafted version moves', () => {
    const s = (key: string, value: boolean) => ({ key, value }) as Switch;
    expect(switchChanges([s('a', true), s('b', false)], { a: false, b: false }).map((x) => x.key)).toEqual(['a']);
  });

  it('keeps her open tag proposals, not the set or yours', () => {
    const tags: Tag[] = [
      { slug: 'a', state: 'proposed', note: null, proposed_by: { kind: 'resident', id: 'r' } },
      { slug: 'b', state: 'active', note: null },
      { slug: 'c', state: 'proposed', note: null, proposed_by: { kind: 'witness', id: 'w' } },
    ];
    expect(proposedTags(tags).map((t) => t.slug)).toEqual(['a']);
  });

  it('tallies predictions with zeros', () => {
    expect(tallyLine({ right: 2 })).toBe('2 right · 0 wrong · 0 void');
  });

  it('offers what the plugin rules allow (brain#68)', () => {
    const labels = (p: PluginEntry, open = false) => pluginActions(p, open).map((a) => a.label);
    expect(labels(plugin({ installed: false, on: false }))).toEqual(['Propose install']);
    expect(labels(plugin({ on: false }))).toEqual(['Propose on', 'Propose removal']);
    expect(labels(plugin({ tier: 'installable' }))).toEqual(['Switch off', 'Propose removal']);
    expect(labels(plugin({}))).toEqual(['Propose off', 'Propose removal']);
    expect(labels(plugin({}), true)).toEqual([]);
  });
});
