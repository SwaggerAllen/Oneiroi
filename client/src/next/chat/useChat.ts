// The conversation's state (P1): the newest page from the query cache,
// so a change notice refreshes it; older pages paged in on demand; the
// turn streaming in; and the outbox, which holds every message the
// witness sends under its own ref until its turn lands (brain#45). The
// outbox and page helpers are the current client's, pure and tested.

import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { Message } from '../../api/types';
import { batched, loadOutbox, newRef, remove, saveOutbox, settle, stuck, update, underWay, type Outgoing } from '../../screens/chat/outbox';
import { compareCursor, mergeNewest, newestCursor } from '../../screens/chat/page';
import type { Live } from '../live/live';
import { useShell } from '../state/store';

const PAGE = 40;

export interface Stream {
  turnRef: string;
  text: string;
}

export function useChat(residentId: string, live: Live) {
  const queries = useQueryClient();
  const setPresence = useShell((s) => s.setPresence);

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
  const [stream, setStream] = useState<Stream | null>(null);
  const [outbox, setOutbox] = useState<Outgoing[]>([]);
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
  }, [newest.data, windowed]);

  // The outbox survives a reload of this browser.
  useEffect(() => {
    if (key) setOutbox(loadOutbox(key));
  }, [key]);
  useEffect(() => {
    if (key) saveOutbox(key, outbox);
  }, [key, outbox]);

  const refreshNewest = useCallback(() => queries.invalidateQueries({ queryKey: newestKey }), [queries, newestKey]);

  // The live stream: presence for the header, the reply as it streams,
  // the outbox's states, and a re-read when a turn lands.
  useEffect(() => {
    if (!key) return;
    return live.session(residentId, key, {
      joined: () => void refreshNewest(),
      started: (ref) => {
        setOutbox((o) => update(o, ref, { state: 'running' }));
        setPresence({ state: 'thinking', since: Date.now() });
      },
      status: (ref, state, detail) => {
        if (state === 'queued') setOutbox((o) => update(o, ref, { state: 'queued' }));
        if (detail?.into) setOutbox((o) => batched(o, ref, detail.into as string));
        if (state === 'thinking' || state === 'tool') {
          setOutbox((o) => update(o, ref, { state, detail: detail?.name }));
          const current = useShell.getState().presence;
          const sameStep = current.state === state && current.detail === detail?.name;
          setPresence({ state, detail: detail?.name, since: sameStep ? current.since : Date.now() });
        }
      },
      delta: (ref, text) => {
        setStream((s) => (s && s.turnRef === ref ? { turnRef: ref, text: s.text + text } : { turnRef: ref, text }));
        const current = useShell.getState().presence;
        if (current.state !== 'writing') setPresence({ state: 'writing', since: Date.now() });
        setOutbox((o) => update(o, ref, { state: 'writing' }));
      },
      turn: () => {
        void refreshNewest().then(() => setStream(null));
        setPresence({ state: 'idle', lastReply: new Date().toISOString() });
      },
      failed: (ref, reason) => {
        setStream(null);
        setOutbox((o) => update(o, ref, { state: 'failed', error: reason }));
        setPresence({ state: 'idle' });
      },
    });
  }, [live, residentId, key, refreshNewest, setPresence]);

  const send = useCallback(
    async (text: string, ref = newRef()) => {
      if (!key || !text.trim()) return;
      const now = Date.now();
      setOutbox((o) =>
        o.some((i) => i.ref === ref)
          ? update(o, ref, { state: 'sending', triedAt: now })
          : [...o, { ref, text, state: 'sending', attempts: 0, sentAt: now, since: now, triedAt: now }],
      );
      try {
        const taken = await api.submit(residentId, key, text, ref);
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

  const discard = useCallback((ref: string) => setOutbox((o) => remove(o, ref)), []);

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
    stream,
    pending,
    working,
    send,
    discard,
    stop,
    jumpTo,
    toNewest,
    windowed,
    newestCursor: newestCursor(messages),
    compareCursor,
  };
}
