// What is generating, per resident, held outside any view (the witness,
// 2026-11-23: "the state for what's generating to live outside of the
// view and keep updating even if you aren't in that workspace"): her
// main chat's session key, the turn under way, and the outbox, which
// holds each message he sent until its turn lands (brain#45). Never the
// conversation itself; that stays in the query cache, read on demand.

import { create } from 'zustand';
import { saveOutbox, type Outgoing } from '../chat/outbox';

/** The turn under way: which it is, never its words (her reply lands whole). */
export interface Stream {
  turnRef: string;
}

export interface Generation {
  key: string | null;
  stream: Stream | null;
  outbox: Outgoing[];
}

const EMPTY: Generation = { key: null, stream: null, outbox: [] };

interface GenerationsState {
  by: Record<string, Generation>;
  /** Changes one resident's generation from what it is now. */
  patch: (residentId: string, change: (g: Generation) => Partial<Generation>) => void;
}

export const useGenerations = create<GenerationsState>((set) => ({
  by: {},
  patch: (residentId, change) =>
    set((s) => {
      const g = s.by[residentId] ?? EMPTY;
      return { by: { ...s.by, [residentId]: { ...g, ...change(g) } } };
    }),
}));

/** One resident's generation, as a hook. */
export const useGeneration = (residentId: string): Generation => useGenerations((s) => s.by[residentId] ?? EMPTY);

/** One resident's generation, read now. */
export const generationOf = (residentId: string): Generation => useGenerations.getState().by[residentId] ?? EMPTY;

// The outbox survives a reload of this browser: written whenever it changes.
useGenerations.subscribe((s, prev) => {
  for (const [id, g] of Object.entries(s.by)) {
    if (g.key && g.outbox !== prev.by[id]?.outbox) saveOutbox(g.key, g.outbox);
  }
});
