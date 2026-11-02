import { describe, expect, it } from 'vitest';
import type { Message } from '../../api/types';
import { compareCursor, firstUnread, mergeNewest, newestCursor, toolSummary } from './page';

const m = (cursor: string | undefined, role = 'assistant'): Message => ({
  cursor,
  session_key: 's',
  turn_ref: 't',
  role,
  content: cursor ?? '',
  sent_at: '2026-11-02T00:00:00Z',
  actor: { kind: 'resident', id: 'r', model: null },
  refusal: false,
});

describe('the transcript pages', () => {
  it('compares cursors as numbers, not strings', () => {
    expect(compareCursor('10:0', '9:3')).toBeGreaterThan(0);
    expect(compareCursor('9:1', '9:3')).toBeLessThan(0);
    expect(compareCursor('4:2', '4:2')).toBe(0);
  });

  it('joins the newest page to what was paged in before it', () => {
    const loaded = [m('1:0'), m('2:0'), m('3:0'), m('4:0')];
    const page = [m('3:0'), m('4:0'), m('5:0')];
    expect(mergeNewest(loaded, page).map((x) => x.cursor)).toEqual(['1:0', '2:0', '3:0', '4:0', '5:0']);
    expect(mergeNewest(loaded, []).length).toBe(0);
    expect(mergeNewest([], page)).toEqual(page);
  });

  it('marks the first message someone else wrote after the last one read, and nothing on a first visit', () => {
    const rows = [m('1:0'), m('2:0', 'user'), m('3:0'), m('4:0')];
    expect(firstUnread(rows, '1:0')).toBe(2);
    expect(firstUnread(rows, '4:0')).toBe(-1);
    expect(firstUnread(rows, null)).toBe(-1);
    expect(newestCursor([m('1:0'), m(undefined)])).toBe('1:0');
  });

  it('folds a tool call to its first line and its size, and leaves a short one alone', () => {
    expect(toolSummary('journal_add({}) -> Added note 3.')).toEqual({ line: 'journal_add({}) -> Added note 3.', more: null });
    expect(toolSummary('a\nb\nc')).toEqual({ line: 'a', more: '3 lines · 5 characters' });
    expect(toolSummary('x'.repeat(2000))).toEqual({ line: `${'x'.repeat(200)}…`, more: '2,000 characters' });
  });
});
