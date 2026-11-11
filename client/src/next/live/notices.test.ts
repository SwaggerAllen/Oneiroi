import { describe, expect, it } from 'vitest';
import { fresh, keysFor, type Notice } from './notices';

const n = (stream: string, position = 1): Notice => ({ kind: 'X', stream, ref: null, position });

describe('notices', () => {
  it('maps a stream to the areas that show it', () => {
    expect(keysFor('r1', n('conversation-main'))).toEqual([
      ['resident', 'r1', 'chat'],
      ['resident', 'r1', 'sessions'],
    ]);
    expect(keysFor('r1', n('journal'))).toEqual([['resident', 'r1', 'time']]);
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
});
