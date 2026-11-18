import { useEffect, useState } from 'react';
import { useSubject } from '../state/resident';
import { type Presence, useShell } from '../state/store';

/** "0:14" from milliseconds. */
export function elapsed(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/**
 * The line under her name (ui-structures.md, client-state.md): the main
 * thread only, thinking vs writing vs a tool, with its timer; the last
 * reply when idle; nothing more specific when the connection is down.
 */
export function presenceLine(p: Presence, connected: boolean, now: number): string {
  const timer = p.since !== undefined ? ` · ${elapsed(now - p.since)}` : '';
  if (!connected) return p.state === 'idle' ? 'offline' : 'offline · her turn may be running';
  switch (p.state) {
    case 'queued':
      return 'queued';
    case 'thinking':
      return `thinking${timer}`;
    case 'writing':
      return `writing${timer}`;
    case 'tool':
      return `${p.detail ?? 'working'}${timer}`;
    default:
      return p.lastReply ? `last reply ${clock(p.lastReply)}` : '';
  }
}

function clock(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/** Ticks once a second while `active`, so a timer on screen moves. */
export function useNow(active: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
}

/**
 * The working indicator for the subject on screen: a resident's own turn,
 * and idle for anyone else's, since one resident's "Thinking…" never
 * belongs on another's screen (2026-11-17).
 */
export function usePresence(): Presence {
  const presence = useShell((s) => s.presence);
  const { id } = useSubject();
  return presence.residentId === undefined || presence.residentId === id ? presence : IDLE;
}

const IDLE: Presence = { state: 'idle' };
