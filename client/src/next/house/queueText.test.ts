import { describe, expect, it } from 'vitest';
import type { QueueCard } from '../../api/types';
import { blockerLine, nameOf, sentence, since, slugify } from './queueText';

const names = { 'resident:l': 'Lily', 'witness:a': 'Andrew' };

const card = (over: Partial<QueueCard> = {}): QueueCard => ({
  act: '3.2',
  task: 3,
  layer: 1,
  type: 'review',
  assignee: 'witness:a',
  status: 'pending',
  view: 'ready',
  gated: false,
  artifact: 'lily:design/queue-ia',
  destination: 'house',
  action: 'promote-to-house',
  optional: false,
  throwback: '3.1',
  waits_on: null,
  blocker: null,
  reason: null,
  pin: null,
  approved_pin: null,
  note: null,
  ready_at: new Date(Date.now() - 2 * 3600 * 1000).toISOString(),
  updated_at: new Date().toISOString(),
  task_title: 'Queue IA',
  project: 'Outreach',
  owner: 'resident:l',
  ...over,
});

describe('the house queue as words (lily:design/queue-ia §2.3)', () => {
  it('reads a card as a sentence', () => {
    expect(sentence(card(), names)).toBe('Review · lily:design/queue-ia · Queue IA › Outreach · ready 2h · Andrew');
  });

  it('names a blocker plainly: its task, its next action and whose it is', () => {
    const blocked = card({
      view: 'blocked',
      waits_on: 7,
      blocker: { number: 7, title: 'Research list', project: 'Outreach', status: 'open', next: { type: 'draft', assignee: 'resident:l' } as never },
    });
    expect(blockerLine(blocked, names)).toBe('blocked on Outreach › Research list · next: draft, Lily');
    expect(blockerLine(card({ view: 'blocked', reason: 'his word' }), names)).toBe('blocked: his word');
    expect(blockerLine(card(), names)).toBeNull();
  });

  it('says who holds it, claude-code and unknown included', () => {
    expect(nameOf(names, 'claude-code')).toBe('Claude Code');
    expect(nameOf(names, 'unknown')).toBe('holder not known yet');
  });

  it('counts time and makes slugs', () => {
    expect(since(new Date(Date.now() - 3 * 86400 * 1000).toISOString())).toBe('3d');
    expect(slugify('The Queue IA: rev 5!')).toBe('the-queue-ia-rev-5');
  });
});
