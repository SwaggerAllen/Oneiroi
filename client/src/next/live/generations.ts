// The watcher (2026-11-23): every awake resident's main chat, joined for
// as long as the app is signed in, whichever workspace is on screen. Its
// events feed the generations store and her indicator, and a turn that
// lands re-reads her newest page, so going back to her chat shows the
// reply that came while you were away, and a turn still running shows as
// running (the join says so, brain#114).

import { useQueryClient, type QueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { api } from '../../api/client';
import { batched, loadOutbox, update } from '../chat/outbox';
import { useGenerations } from '../state/generations';
import { useShell } from '../state/store';
import type { Live, SessionEvents } from './live';

const working = (residentId: string) => {
  const p = useShell.getState().presences[residentId];
  return p !== undefined && p.state !== 'idle';
};

/** The session events of one resident's main chat, written to the store. */
export function eventsFor(residentId: string, key: string, queries: QueryClient): SessionEvents {
  const { patch } = useGenerations.getState();
  const { setPresence } = useShell.getState();
  const newest = () => queries.invalidateQueries({ queryKey: ['resident', residentId, 'chat', key, 'newest'] });

  return {
    joined: ({ running, queued }) => {
      patch(residentId, (g) => ({
        stream: running ? { turnRef: running } : null,
        outbox: g.outbox.map((i) => (i.ref === running ? { ...i, state: 'running' } : queued.includes(i.ref) ? { ...i, state: 'queued' } : i)),
      }));
      if (running && !working(residentId)) setPresence({ residentId, state: 'thinking', since: Date.now() });
      if (!running && working(residentId)) setPresence({ residentId, state: 'idle' });
      // Whatever landed while nobody listened.
      void newest();
      void queries.invalidateQueries({ queryKey: ['resident', residentId, 'capture-failures'] });
    },
    started: (ref) => {
      // Her reply is not streamed (the witness, 2026-11-21): the turn shows
      // as working, its step and time, and lands whole.
      patch(residentId, (g) => ({ stream: { turnRef: ref }, outbox: update(g.outbox, ref, { state: 'running' }) }));
      setPresence({ residentId, state: 'thinking', since: Date.now() });
    },
    status: (ref, state, detail) => {
      if (state === 'queued') patch(residentId, (g) => ({ outbox: update(g.outbox, ref, { state: 'queued' }) }));
      if (detail?.into) patch(residentId, (g) => ({ outbox: batched(g.outbox, ref, detail.into as string) }));
      if (state === 'thinking' || state === 'tool') {
        patch(residentId, (g) => ({ outbox: update(g.outbox, ref, { state, detail: detail?.name }) }));
        const current = useShell.getState().presences[residentId];
        const sameStep = current?.state === state && current?.detail === detail?.name;
        setPresence({ residentId, state, detail: detail?.name, since: sameStep ? current?.since : Date.now() });
      }
    },
    turn: () => {
      void newest().then(() => patch(residentId, () => ({ stream: null })));
      setPresence({ residentId, state: 'idle', lastReply: new Date().toISOString() });
    },
    failed: (ref, reason) => {
      void queries.invalidateQueries({ queryKey: ['resident', residentId, 'capture-failures'] });
      patch(residentId, (g) => ({ stream: null, outbox: update(g.outbox, ref, { state: 'failed', error: reason }) }));
      setPresence({ residentId, state: 'idle' });
    },
  };
}

/** Joins every resident's main chat on the app's one socket, for as long as the app is signed in. */
export function useGenerationWatcher(live: Live, residentIds: string[]) {
  const queries = useQueryClient();
  const ids = residentIds.join(',');
  useEffect(() => {
    let stopped = false;
    const leaves: Array<() => void> = [];
    for (const id of ids ? ids.split(',') : []) {
      void queries
        .fetchQuery({ queryKey: ['resident', id, 'chat', 'main'], queryFn: () => api.mainSession(id), staleTime: Infinity })
        .then(({ key }) => {
          if (stopped) return;
          useGenerations.getState().patch(id, (g) => (g.key === key ? {} : { key, outbox: loadOutbox(key) }));
          leaves.push(live.session(id, key, eventsFor(id, key, queries)));
        })
        .catch(() => undefined);
    }
    return () => {
      stopped = true;
      for (const leave of leaves) leave();
    };
  }, [live, ids, queries]);
}
