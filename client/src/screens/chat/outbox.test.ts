import { describe, expect, it } from 'vitest';
import { itemLine, newRef, type Outgoing, settle, statusLine, update } from './outbox';

const item = (ref: string, state: Outgoing['state'], more: Partial<Outgoing> = {}): Outgoing => ({ ref, text: ref, state, attempts: 0, ...more });

describe('outbox', () => {
  it('mints refs the server accepts', () => {
    const ref = newRef();
    expect(ref).toMatch(/^[A-Za-z0-9_-]{8,64}$/);
    expect(newRef()).not.toBe(ref);
  });

  it('settles a message once its turn is in the transcript with a reply', () => {
    const items = [item('a', 'running'), item('b', 'queued')];
    expect(settle(items, new Set(['a']))).toEqual([item('b', 'queued')]);
    expect(update(items, 'b', { state: 'thinking' })[1].state).toBe('thinking');
  });

  it('lets the newest message on its way speak for the header, and is quiet when none is', () => {
    expect(statusLine([], 'Lily')).toBeNull();
    expect(statusLine([item('a', 'unsent'), item('b', 'failed')], 'Lily')).toBeNull();
    expect(statusLine([item('a', 'sending')], 'Lily')).toBe('Sending…');
    expect(statusLine([item('a', 'thinking')], 'Lily')).toBe('Lily is thinking…');
    expect(statusLine([item('a', 'tool', { detail: 'bookmark_add' })], 'Lily')).toBe('Lily is using bookmark_add…');
  });

  it('says why a message did not go or was not answered', () => {
    expect(itemLine(item('a', 'unsent', { error: 'text is required' }), 'Lily')).toBe('not sent: text is required');
    expect(itemLine(item('a', 'failed'), 'Lily')).toBe("Lily couldn't answer");
  });
});
