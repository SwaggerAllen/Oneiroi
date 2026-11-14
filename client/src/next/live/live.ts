// One socket for everything (client-state.md): the resident's change
// notices now, the open session's stream in P1. The socket token lives
// five minutes (brain#6), so it is re-minted before each (re)connect.

import type { QueryClient } from '@tanstack/react-query';
import { Socket, type Channel } from 'phoenix';
import { api } from '../../api/client';
import { useShell } from '../state/store';
import { fresh, keysFor, type Notice } from './notices';

const CURSOR_KEY = 'oneiroi.next.cursor';

export interface SessionEvents {
  joined: () => void;
  started: (turnRef: string) => void;
  delta: (turnRef: string, text: string) => void;
  status: (turnRef: string, state: string, detail: { name?: string; ahead?: number; into?: string } | null) => void;
  turn: (turnRef: string) => void;
  failed: (turnRef: string, reason: string) => void;
}

function storedCursor(residentId: string): number | null {
  try {
    const raw = localStorage.getItem(`${CURSOR_KEY}.${residentId}`);
    return raw ? Number(raw) : null;
  } catch {
    return null;
  }
}

function storeCursor(residentId: string, position: number) {
  try {
    localStorage.setItem(`${CURSOR_KEY}.${residentId}`, String(position));
  } catch {
    // private window or blocked storage: the cursor only saves a refetch
  }
}

// How long a burst of notices is gathered before what it touched is read again.
const COALESCE_MS = 750;

export class Live {
  private socket: Socket | null = null;
  private token = '';
  private stopped = false;
  private resident: Channel | null = null;
  private seen = new Set<number>();

  private readonly queries: QueryClient;
  private markReady: () => void = () => undefined;
  /** Settles once the socket exists; joins asked for earlier wait on it. */
  readonly ready: Promise<void>;

  constructor(queries: QueryClient) {
    this.queries = queries;
    this.ready = new Promise((resolve) => (this.markReady = resolve));
  }

  async start() {
    this.token = (await api.socketToken()).token;
    // A stopped Live says nothing: its socket's close lands after the next
    // subject's socket opened, and would mark that one offline.
    const set = (c: Parameters<ReturnType<typeof useShell.getState>['setConnection']>[0]) => {
      if (!this.stopped) useShell.getState().setConnection(c);
    };
    this.socket = new Socket('/socket', { params: () => ({ token: this.token }) });
    this.socket.onOpen(() => set('connected'));
    this.socket.onError(() => {
      set('offline');
      void this.refreshToken();
    });
    this.socket.onClose(() => set('offline'));
    set('connecting');
    this.socket.connect();
    this.markReady();
  }

  /** The frustration button that does real work: reconnect now, not after the backoff. */
  async reconnect() {
    useShell.getState().setConnection('connecting');
    await this.refreshToken();
    this.socket?.disconnect(() => this.socket?.connect());
  }

  private async refreshToken() {
    try {
      this.token = (await api.socketToken()).token;
    } catch {
      // offline or signed out: the next attempt tries again
    }
  }

  /** Joins a resident's notices, resuming from the last position this device saw. */
  watch(residentId: string) {
    if (!this.socket) return;
    this.resident?.leave();
    this.seen.clear();
    const since = storedCursor(residentId);
    const channel = this.socket.channel(
      `resident:${residentId}`,
      () => (since === null ? {} : { since: useShell.getState().cursor ?? since }),
    );

    // A burst of notices (a turn's every write folds a projection) is
    // coalesced into one invalidation per key, a moment after the burst,
    // and a read already in flight is kept rather than started again:
    // each abandoned read still runs on the server, and on 2026-11-13 a
    // dozen of them held the connection pool while her free time needed
    // it (brain_turn_crashed at 22:31Z).
    const pending = new Map<string, unknown[]>();
    let flush: ReturnType<typeof setTimeout> | null = null;
    const invalidate = () => {
      flush = null;
      const keys = [...pending.values()];
      pending.clear();
      for (const queryKey of keys) void this.queries.invalidateQueries({ queryKey }, { cancelRefetch: false });
    };

    const apply = (notice: Notice) => {
      if (!fresh(this.seen, notice)) return;
      for (const queryKey of keysFor(residentId, notice)) pending.set(JSON.stringify(queryKey), queryKey);
      if (flush === null) flush = setTimeout(invalidate, COALESCE_MS);
      useShell.getState().setCursor(notice.position);
      storeCursor(residentId, notice.position);
    };

    channel.on('notice', (n: Notice) => apply(n));
    // The bell's list, computed by the server once a burst and pushed
    // whole (brain#94): it replaces the read, so no notice reads it again.
    channel.on('needs_you', ({ entries }: { entries: unknown[] }) => {
      this.queries.setQueryData(['resident', residentId, 'bell'], entries);
    });
    channel.on('notices', ({ notices }: { notices: Notice[] }) => notices.forEach(apply));
    channel.on('reset', ({ position }: { position: number }) => {
      void this.queries.invalidateQueries({ queryKey: ['resident', residentId] });
      useShell.getState().setCursor(position);
      storeCursor(residentId, position);
    });
    channel
      .join()
      .receive('ok', ({ position }: { position: number }) => {
        // First visit on this device: nothing to replay, start from now.
        if (since === null) {
          useShell.getState().setCursor(position);
          storeCursor(residentId, position);
        }
      });
    this.resident = channel;
  }

  /**
   * Joins a session's stream (spec §5, brain#45) on the same socket:
   * turn_started, delta, status, turn, failed. Returns a leave function.
   */
  session(residentId: string, key: string, on: SessionEvents): () => void {
    let channel: Channel | null = null;
    let left = false;
    void this.ready.then(() => {
      if (left || !this.socket) return;
      channel = this.join(residentId, key, on);
    });
    return () => {
      left = true;
      channel?.leave();
    };
  }

  private join(residentId: string, key: string, on: SessionEvents): Channel {
    const channel = (this.socket as Socket).channel(`session:${residentId}:${key}`);
    channel.on('turn_started', (p: { turn_ref: string }) => on.started(p.turn_ref));
    channel.on('delta', (p: { turn_ref: string; text: string }) => on.delta(p.turn_ref, p.text));
    channel.on('status', (p: { turn_ref: string; state: string; detail: { name?: string; ahead?: number; into?: string } | null }) =>
      on.status(p.turn_ref, p.state, p.detail),
    );
    channel.on('turn', (p: { turn_ref: string }) => on.turn(p.turn_ref));
    channel.on('failed', (p: { turn_ref: string; reason: string }) => on.failed(p.turn_ref, p.reason));
    // A rejoin after an outage: what landed meanwhile is read again.
    channel.join().receive('ok', () => on.joined());
    return channel;
  }

  stop() {
    this.stopped = true;
    this.resident?.leave();
    this.socket?.disconnect();
  }
}
