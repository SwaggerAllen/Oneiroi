import { QueryClient } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { useGenerations } from '../state/generations';
import { useShell } from '../state/store';
import { eventsFor } from './generations';

// What is generating, kept outside the view (2026-11-23): the watcher's
// events write the store whichever workspace is on screen.
describe('the generation watcher', () => {
  let queries: QueryClient;

  beforeEach(() => {
    useGenerations.setState({ by: {} });
    useShell.setState({ presence: { state: 'idle' }, presences: {} });
    queries = new QueryClient();
  });

  const sent = (ref: string) => ({ ref, text: 'hello', state: 'sending' as const, attempts: 0, sentAt: 0, since: 0, triedAt: 0 });

  it('coming back mid-turn shows it running, from what the join says', () => {
    useGenerations.getState().patch('lily', () => ({ key: 'k', outbox: [sent('t1'), sent('t2')] }));
    eventsFor('lily', 'k', queries).joined({ running: 't1', queued: ['t2'] });

    const g = useGenerations.getState().by.lily;
    expect(g.stream).toEqual({ turnRef: 't1' });
    expect(g.outbox.map((i) => i.state)).toEqual(['running', 'queued']);
    expect(useShell.getState().presences.lily.state).toBe('thinking');
  });

  it('a reply that lands while you are elsewhere re-reads her chat and settles her indicator', async () => {
    const invalidate = vi.spyOn(queries, 'invalidateQueries');
    const events = eventsFor('lily', 'k', queries);
    events.started('t1');
    expect(useGenerations.getState().by.lily.stream).toEqual({ turnRef: 't1' });

    events.turn('t1');
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ['resident', 'lily', 'chat', 'k', 'newest'] });
    expect(useShell.getState().presences.lily.state).toBe('idle');
    await vi.waitFor(() => expect(useGenerations.getState().by.lily.stream).toBeNull());
  });

  it("joined after the turn ended clears what was left running; one resident's events never touch another's", () => {
    eventsFor('scarlett', 'k2', queries).started('s1');
    const lily = eventsFor('lily', 'k', queries);
    lily.started('t1');
    lily.joined({ running: null, queued: [] });

    expect(useGenerations.getState().by.lily.stream).toBeNull();
    expect(useShell.getState().presences.lily.state).toBe('idle');
    expect(useGenerations.getState().by.scarlett.stream).toEqual({ turnRef: 's1' });
    expect(useShell.getState().presences.scarlett.state).toBe('thinking');
  });
});
