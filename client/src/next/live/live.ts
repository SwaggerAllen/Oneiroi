// One socket for everything (client-state.md): the resident's change
// notices now, the open session's stream in P1. The socket token lives
// five minutes (brain#6), so it is re-minted before each (re)connect.

import type { QueryClient } from '@tanstack/react-query';
import { Socket, type Channel } from 'phoenix';
import { api } from '../../api/client';
import { useShell } from '../state/store';
import { fresh, keysFor, type Notice } from './notices';

const CURSOR_KEY = 'oneiroi.next.cursor';

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

export class Live {
  private socket: Socket | null = null;
  private token = '';
  private resident: Channel | null = null;
  private seen = new Set<number>();

  private readonly queries: QueryClient;

  constructor(queries: QueryClient) {
    this.queries = queries;
  }

  async start() {
    this.token = (await api.socketToken()).token;
    const set = useShell.getState().setConnection;
    this.socket = new Socket('/socket', { params: () => ({ token: this.token }) });
    this.socket.onOpen(() => set('connected'));
    this.socket.onError(() => {
      set('offline');
      void this.refreshToken();
    });
    this.socket.onClose(() => set('offline'));
    set('connecting');
    this.socket.connect();
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

    const apply = (notice: Notice) => {
      if (!fresh(this.seen, notice)) return;
      for (const queryKey of keysFor(residentId, notice)) void this.queries.invalidateQueries({ queryKey });
      useShell.getState().setCursor(notice.position);
      storeCursor(residentId, notice.position);
    };

    channel.on('notice', (n: Notice) => apply(n));
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

  stop() {
    this.resident?.leave();
    this.socket?.disconnect();
  }
}
