// The conversation's state (P1): the newest page from the query cache,
// so a change notice refreshes it; older pages paged in on demand. What
// is generating (the turn under way, the outbox holding every message the
// witness sends under its own ref until its turn lands, brain#45) lives
// outside the view, in the generations store, kept by the app-wide
// watcher (`live/generations.ts`) whichever workspace is on screen.

import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { Message } from '../../api/types';
import { failedFrom, loadOutbox, newRef, remove, settle, stuck, update, underWay, type Outgoing } from './outbox';
import { compareCursor, mergeNewest, newestCursor } from './page';
import { useGeneration, useGenerations, type Stream } from '../state/generations';

const PAGE = 40;

export type { Stream };

export function useChat(residentId: string) {
  const queries = useQueryClient();

  const main = useQuery({
    queryKey: ['resident', residentId, 'chat', 'main'],
    queryFn: () => api.mainSession(residentId),
    staleTime: Infinity,
  });
  const key = main.data?.key ?? null;

  const newestKey = useMemo(() => ['resident', residentId, 'chat', key, 'newest'], [residentId, key]);
  const newest = useQuery({
    queryKey: newestKey,
    queryFn: () => api.transcriptPage(residentId, key as string, PAGE),
    enabled: key !== null,
  });

  const [messages, setMessages] = useState<Message[]>([]);
  const [more, setMore] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  // What is generating: the store's, kept while this view is away.
  const generation = useGeneration(residentId);
  const stream = generation.stream;
  const outbox = generation.outbox;
  const setOutbox = useCallback(
    (change: (o: Outgoing[]) => Outgoing[]) => useGenerations.getState().patch(residentId, (g) => ({ outbox: change(g.outbox) })),
    [residentId],
  );
  const outboxRef = useRef<Outgoing[]>([]);
  useEffect(() => {
    outboxRef.current = outbox;
  }, [outbox]);
  const pagedBack = useRef(false);
  // A jump far back (the navigator) reads a window around its anchor; the
  // newest page stops merging in until the reader returns to the end.
  const [windowed, setWindowed] = useState<{ anchor: string; moreAfter: boolean } | null>(null);

  // The newest page merged in whenever it is read again.
  useEffect(() => {
    if (!newest.data || windowed) return;
    setMessages((loaded) => mergeNewest(loaded, newest.data.messages));
    // Once older pages are in, whether more remain is theirs to say.
    if (!pagedBack.current) setMore(newest.data.more);
    // A turn's messages landing settle its outbox entries.
    const answered = new Set(newest.data.messages.map((m) => m.turn_ref));
    setOutbox((items) => settle(items, answered));
  }, [newest.data, windowed, setOutbox]);

  // Her main chat's key in the store, its outbox read back from this
  // browser, when the watcher has not set it yet (it persists from there).
  useEffect(() => {
    if (key && useGenerations.getState().by[residentId]?.key !== key) useGenerations.getState().patch(residentId, () => ({ key, outbox: loadOutbox(key) }));
  }, [residentId, key]);

  const refreshNewest = useCallback(() => queries.invalidateQueries({ queryKey: newestKey }), [queries, newestKey]);

  const send = useCallback(
    async (text: string, ref = newRef(), domain?: string | null) => {
      if (!key || !text.trim()) return;
      const now = Date.now();
      // Sent again, it keeps the domain it was first sent in.
      const held = outboxRef.current.find((i) => i.ref === ref);
      const named = held ? held.domain : domain;
      setOutbox((o) =>
        o.some((i) => i.ref === ref)
          ? update(o, ref, { state: 'sending', triedAt: now })
          : [...o, { ref, text, state: 'sending', attempts: 0, sentAt: now, since: now, triedAt: now, ...(domain === undefined ? {} : { domain }) }],
      );
      try {
        const taken = await api.submit(residentId, key, text, ref, named);
        if (taken.state === 'queued') setOutbox((o) => update(o, ref, { state: 'queued' }));
        if (taken.state === 'running') setOutbox((o) => update(o, ref, { state: 'running' }));
        // Taken before, here or by a process a restart ended: held as
        // queued, and the stuck check sends it again past the timeout.
        if (taken.state === 'duplicate') setOutbox((o) => update(o, ref, { state: 'queued' }));
      } catch (e) {
        setOutbox((o) => update(o, ref, { state: 'unsent', error: (e as Error).message, attempts: (o.find((i) => i.ref === ref)?.attempts ?? 0) + 1 }));
      }
    },
    [residentId, key],
  );

  // Every half minute, a message stuck past the server's turn timeout is
  // sent again under its own ref (see `stuck`).
  useEffect(() => {
    if (!key) return;
    const tick = setInterval(() => {
      for (const item of stuck(outboxRef.current)) void send(item.text, item.ref);
    }, 30_000);
    return () => clearInterval(tick);
  }, [key, send]);

  const discard = useCallback((ref: string) => setOutbox((o) => remove(o, ref)), [setOutbox]);

  // The conversation's current domain (kumbukumbu#72), as the newest page
  // reads it, and a turn renamed after the fact.
  const domainNow = newest.data?.session.domain ?? null;
  const tagTurn = useCallback(
    async (turnRef: string, domain: string | null) => {
      if (!key) return;
      await api.tagDomain(residentId, key, turnRef, domain);
      await refreshNewest();
    },
    [residentId, key, refreshNewest],
  );

  // The turns that failed and are not yet settled (brain#54, #88), read on
  // arrival and every minute: a failure broadcast while the page was away
  // still marks its message, and a scheduled turn's failure (a check-in,
  // with no message of his waiting) shows as a line of its own.
  const failuresKey = useMemo(() => ['resident', residentId, 'capture-failures'], [residentId]);
  const failures = useQuery({ queryKey: failuresKey, queryFn: () => api.captureFailures(residentId), enabled: !!key, refetchInterval: 60_000 });
  useEffect(() => {
    if (failures.data) setOutbox((o) => failedFrom(o, failures.data));
  }, [failures.data, setOutbox]);
  const unanswered = (failures.data ?? []).filter(
    (f) => f.session_key === key && !outbox.some((i) => i.ref === f.turn_ref || i.into === f.turn_ref) && !messages.some((m) => m.turn_ref === f.turn_ref && m.role === 'assistant'),
  );
  const dismissFailure = useCallback(
    async (turnRef: string) => {
      if (!key) return;
      await api.resolveFailure(residentId, key, turnRef, 'dismissed from the chat').catch(() => undefined);
      void queries.invalidateQueries({ queryKey: failuresKey });
      void queries.invalidateQueries({ queryKey: ['resident', residentId, 'bell'] });
    },
    [residentId, key, queries, failuresKey],
  );
  // Run it again, as what it was (brain#89); the turn arrives on the channel.
  const retryFailure = useCallback(
    async (turnRef: string) => {
      await api.retryFailure(residentId, turnRef).catch(() => undefined);
      void queries.invalidateQueries({ queryKey: failuresKey });
      void queries.invalidateQueries({ queryKey: ['resident', residentId, 'bell'] });
    },
    [residentId, queries, failuresKey],
  );

  const stop = useCallback(async () => {
    if (key) await api.stopTurn(residentId, key).catch(() => undefined);
  }, [residentId, key]);

  const loadOlder = useCallback(async () => {
    if (!key || loadingOlder || !more) return;
    const oldest = messages.find((m) => m.cursor)?.cursor;
    if (!oldest) return;
    setLoadingOlder(true);
    pagedBack.current = true;
    try {
      const page = await api.transcriptPage(residentId, key, PAGE, oldest);
      setMessages((loaded) => {
        const known = new Set(loaded.map((m) => m.cursor));
        return [...page.messages.filter((m) => !known.has(m.cursor)), ...loaded];
      });
      setMore(page.more);
    } finally {
      setLoadingOlder(false);
    }
  }, [residentId, key, loadingOlder, more, messages]);

  // Reading on past a jump's window (kumbukumbu#96): the next page after
  // its last message; when none remain, the window meets the newest and
  // the chat is live again.
  const [loadingNewer, setLoadingNewer] = useState(false);
  const loadNewer = useCallback(async () => {
    if (!key || !windowed?.moreAfter || loadingNewer) return;
    const last = [...messages].reverse().find((m) => m.cursor)?.cursor;
    if (!last) return;
    setLoadingNewer(true);
    try {
      const page = await api.transcriptAfter(residentId, key, last, PAGE);
      setMessages((loaded) => {
        const known = new Set(loaded.map((m) => m.cursor));
        return [...loaded, ...page.messages.filter((m) => !known.has(m.cursor))];
      });
      if (page.more) setWindowed((w) => (w ? { ...w, moreAfter: true } : w));
      else {
        pagedBack.current = false;
        setWindowed(null);
      }
    } finally {
      setLoadingNewer(false);
    }
  }, [residentId, key, windowed, loadingNewer, messages]);

  const jumpTo = useCallback(
    async (anchor: string) => {
      if (!key) return;
      const page = await api.transcriptAround(residentId, key, anchor, PAGE);
      pagedBack.current = true;
      setMessages(page.messages);
      setMore(page.more_before);
      setWindowed({ anchor: page.anchor ?? anchor, moreAfter: page.more_after });
    },
    [residentId, key],
  );

  const toNewest = useCallback(() => {
    pagedBack.current = false;
    setWindowed(null);
    if (newest.data) {
      setMessages(newest.data.messages);
      setMore(newest.data.more);
    }
  }, [newest.data]);

  const working = outbox.some((i) => underWay.includes(i.state)) || stream !== null;
  const pending = outbox.filter((i) => !messages.some((m) => m.turn_ref === i.ref || (i.into && m.turn_ref === i.into)));

  return {
    key,
    ready: newest.isSuccess,
    messages,
    more,
    loadingOlder,
    loadOlder,
    loadingNewer,
    loadNewer,
    stream,
    pending,
    working,
    send,
    discard,
    domainNow,
    tagTurn,
    unanswered,
    dismissFailure,
    retryFailure,
    stop,
    jumpTo,
    toNewest,
    windowed,
    newestCursor: newestCursor(messages),
    compareCursor,
  };
}
