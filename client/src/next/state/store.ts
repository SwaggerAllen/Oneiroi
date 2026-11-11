// Device state (client-state.md): what only this device knows. Server
// state lives in the query cache, never here.

import { create } from 'zustand';
import { DEFAULT_SEEDS, type Seeds } from '../theme/derive';
import { TABS, type Location, type SettingsSection, type Tab } from './routes';

export type Connection = 'connected' | 'connecting' | 'offline';
export type Overlay = 'bell' | 'push' | 'settings' | 'feedback' | 'theme' | 'subject' | null;

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
  /** A settings page open over the tabs (`#/settings/<section>`), or none. */
  page: SettingsSection | null;
  /** The seeds on screen now: a try-on, else this device's override, else hers (P8). */
  seeds: Seeds;
  /** Seeds worn for a moment, to judge a proposal or an edit before keeping it. */
  tryOn: Seeds | null;
  setSeeds: (s: Seeds) => void;
  setTryOn: (s: Seeds | null) => void;
  setOverlay: (o: Overlay) => void;
  /** A new subject: every tab back to its root, since the old paths were the other resident's. */
  resetStacks: () => void;
  setPage: (p: SettingsSection | null) => void;
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
  page: null,
  seeds: DEFAULT_SEEDS,
  tryOn: null,
  setSeeds: (seeds) => set({ seeds }),
  setTryOn: (tryOn) => set({ tryOn }),
  setOverlay: (overlay) => set({ overlay }),
  resetStacks: () => set({ stacks: roots(), tab: 'chat', page: null }),
  setPage: (page) => set({ page }),

  // Arriving from the URL (load, back/forward): the tab becomes active and
  // its stack is cut back to the path if it is on it, or the path pushed.
  go: ({ tab, path }) =>
    set((s) => {
      const stack = s.stacks[tab];
      const at = stack.lastIndexOf(path);
      const next = at >= 0 ? stack.slice(0, at + 1) : [...stack, path];
      return { tab, page: null, stacks: { ...s.stacks, [tab]: next } };
    }),
  push: (path) =>
    set((s) => ({ stacks: { ...s.stacks, [s.tab]: [...s.stacks[s.tab], path] } })),
  back: () =>
    set((s) => {
      const stack = s.stacks[s.tab];
      return stack.length > 1 ? { stacks: { ...s.stacks, [s.tab]: stack.slice(0, -1) } } : {};
    }),
  // Switching tabs keeps every stack: the tab comes back where it was.
  // A tab tapped under a settings page closes the page.
  setTab: (tab) => set({ tab, page: null }),
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
