// Device state (client-state.md): what only this device knows. Server
// state lives in the query cache, never here.

import { create } from 'zustand';
import { TABS, type Location, type Tab } from './routes';

export type Connection = 'connected' | 'connecting' | 'offline';
export type Overlay = 'bell' | 'push' | 'settings' | 'feedback' | null;

export interface Presence {
  state: 'idle' | 'queued' | 'thinking' | 'writing' | 'tool';
  detail?: string; // the tool's name
  since?: number; // ms epoch, for the timer
  lastReply?: string; // ISO instant
}

interface ShellState {
  tab: Tab;
  stacks: Record<Tab, string[]>; // each tab's stack of paths; [''] is its root
  connection: Connection;
  offlineSince: number | null;
  cursor: number | null; // the last notice position seen (apsu#24)
  presence: Presence;
  searchOpen: boolean;
  overlay: Overlay;
  setOverlay: (o: Overlay) => void;
  go: (to: Location) => void;
  push: (path: string) => void;
  back: () => void;
  setTab: (tab: Tab) => void;
  setConnection: (c: Connection, now?: number) => void;
  setCursor: (p: number) => void;
  setPresence: (p: Presence) => void;
  setSearchOpen: (open: boolean) => void;
}

const roots = () => Object.fromEntries(TABS.map((t) => [t, ['']])) as Record<Tab, string[]>;

export const useShell = create<ShellState>((set) => ({
  tab: 'chat',
  stacks: roots(),
  connection: 'connecting',
  offlineSince: null,
  cursor: null,
  presence: { state: 'idle' },
  searchOpen: false,
  overlay: null,
  setOverlay: (overlay) => set({ overlay }),

  // Arriving from the URL (load, back/forward): the tab becomes active and
  // its stack is cut back to the path if it is on it, or the path pushed.
  go: ({ tab, path }) =>
    set((s) => {
      const stack = s.stacks[tab];
      const at = stack.lastIndexOf(path);
      const next = at >= 0 ? stack.slice(0, at + 1) : [...stack, path];
      return { tab, stacks: { ...s.stacks, [tab]: next } };
    }),
  push: (path) =>
    set((s) => ({ stacks: { ...s.stacks, [s.tab]: [...s.stacks[s.tab], path] } })),
  back: () =>
    set((s) => {
      const stack = s.stacks[s.tab];
      return stack.length > 1 ? { stacks: { ...s.stacks, [s.tab]: stack.slice(0, -1) } } : {};
    }),
  // Switching tabs keeps every stack: the tab comes back where it was.
  setTab: (tab) => set({ tab }),
  setConnection: (connection, now = Date.now()) =>
    set((s) => ({
      connection,
      offlineSince: connection === 'connected' ? null : (s.offlineSince ?? now),
    })),
  setCursor: (cursor) => set((s) => ({ cursor: Math.max(cursor, s.cursor ?? 0) })),
  setPresence: (presence) => set({ presence }),
  setSearchOpen: (searchOpen) => set({ searchOpen }),
}));

export const topOf = (stacks: Record<Tab, string[]>, tab: Tab) => stacks[tab][stacks[tab].length - 1];
