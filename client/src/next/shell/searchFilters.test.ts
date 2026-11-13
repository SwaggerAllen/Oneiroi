import { describe, expect, it } from 'vitest';
import { activeCount, NO_FILTERS, toParams } from './searchFilters';

describe('search filters (kumbukumbu#69)', () => {
  it('sends only what is set, in the server’s names, for the scope asked', () => {
    const f = { ...NO_FILTERS, kinds: ['writing', 'design'], author: 'resident' as const, who: 'witness' as const, pinned: true };
    expect(toParams('records', f)).toEqual({ kinds: 'writing,design', author: 'resident' });
    expect(toParams('words', f)).toEqual({ page: '1', sort: 'newest', who: 'witness' });
    expect(toParams('bookmarks', f)).toEqual({ pinned: 'true' });
    expect(toParams('everything', f)).toEqual({});
  });

  it('a date range says which date for records, and the order goes only when it is not relevance', () => {
    const f = { ...NO_FILTERS, from: '2026-11-01', date: 'created' as const, sort: 'oldest' as const };
    const p = toParams('records', f);
    expect(p).toMatchObject({ date: 'created', sort: 'oldest', from: new Date(2026, 10, 1).toISOString() });
    expect(toParams('records', { ...NO_FILTERS })).toEqual({});
  });

  it('transcripts page and never rank by relevance', () => {
    expect(toParams('words', { ...NO_FILTERS, sort: 'relevance' }, 3)).toEqual({ page: '3', sort: 'newest' });
  });

  it('counts the filters set for a scope', () => {
    const f = { ...NO_FILTERS, from: '2026-11-01', mood: 'glad', tag: 'birds' };
    expect(activeCount('scenes', f)).toBe(2);
    expect(activeCount('bookmarks', f)).toBe(2);
    expect(activeCount('records', f)).toBe(1);
  });
});
