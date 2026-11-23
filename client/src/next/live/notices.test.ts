import { describe, expect, it } from 'vitest';
import { DOC_CONTEXT, fresh, houseKeys, keysFor, type Notice } from './notices';

const n = (stream: string, position = 1): Notice => ({ kind: 'X', stream, ref: null, position });

describe('notices', () => {
  it('maps a stream to the areas that show it', () => {
    expect(keysFor('r1', n('conversation-main'))).toEqual([
      ['resident', 'r1', 'chat'],
      ['resident', 'r1', 'sessions'],
    ]);
    expect(keysFor('r1', n('journal'))).toEqual([['resident', 'r1', 'time']]);
  });

  it('never reads the bell again for a notice: its list is pushed (brain#94)', () => {
    expect(keysFor('r1', n('work'))).toEqual([
      ['resident', 'r1', 'sessions'],
      ['resident', 'r1', 'bell', 'hers'],
      ['resident', 'r1', 'settings'],
    ]);
  });

  it('invalidates the whole resident for a stream it does not know', () => {
    expect(keysFor('r1', n('something-new'))).toEqual([['resident', 'r1']]);
  });

  it('coalesces the same position announced by several projectors', () => {
    const seen = new Set<number>();
    expect(fresh(seen, n('memory', 7))).toBe(true);
    expect(fresh(seen, n('memory', 7))).toBe(false);
    expect(fresh(seen, n('memory', 8))).toBe(true);
  });

  it('reads her threads and the document screens again when a thread of hers is written', () => {
    expect(keysFor('r1', { kind: 'ThreadWritten', stream: 'threads', ref: 'threads/7', position: 3 })).toEqual([['resident', 'r1', 'threads'], DOC_CONTEXT]);
  });

  it('reads the queue again for a queue notice, and the house and unread for a thread', () => {
    expect(houseKeys(n('queue'))).toEqual([['household', 'queue']]);
    expect(houseKeys(n('threads'))).toEqual([['household'], ['unread']]);
  });
});
