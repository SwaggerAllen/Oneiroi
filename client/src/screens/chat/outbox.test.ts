import { describe, expect, it } from 'vitest';
import { elapsed, failedFrom, itemLine, newRef, type Outgoing, settle, statusLine, update } from './outbox';

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

  // brain#54: the witness waited minutes on "thinking" with nothing to
  // say how long, or that the turn had failed while the page was away.
  it('times the present state, keeps the timer across the same state, and says when it was sent', () => {
    const sent = update([item('a', 'sending')], 'a', { state: 'running' }, 1_000);
    expect(sent[0]).toMatchObject({ sentAt: 1_000, since: 1_000 });
    const again = update(sent, 'a', { state: 'running', attempts: 1 }, 50_000);
    expect(again[0].since).toBe(1_000);
    const tool = update(again, 'a', { state: 'tool', detail: 'bookmark_list' }, 100_000);
    expect(tool[0]).toMatchObject({ sentAt: 1_000, since: 100_000 });
    expect(statusLine(tool, 'Lily', 142_000)).toBe('Lily is using bookmark_list… 42s · sent 2m 21s ago');
    expect(statusLine(sent, 'Lily', 3_000)).toBe('Lily is thinking… 2s');
    expect(elapsed(3_725_000)).toBe('1h 02m');
  });

  it('reads a failure the server recorded onto the message it belongs to', () => {
    const items = [item('a', 'thinking'), item('b', 'running'), item('c', 'failed', { error: 'earlier' })];
    const after = failedFrom(items, [
      { turn_ref: 'a', reason: 'nisaba_provider_failed' },
      { turn_ref: 'c', reason: 'later' },
    ]);
    expect(after.map((i) => [i.state, i.error])).toEqual([
      ['failed', 'nisaba_provider_failed'],
      ['running', undefined],
      ['failed', 'earlier'],
    ]);
  });

  it('says why a message did not go or was not answered', () => {
    expect(itemLine(item('a', 'unsent', { error: 'text is required' }), 'Lily')).toBe('not sent: text is required');
    expect(itemLine(item('a', 'failed'), 'Lily')).toBe("Lily couldn't answer");
  });
});
