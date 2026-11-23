import { create } from 'zustand';
import { TIMING } from '../shell/motion';
import { queries } from './queries';

// Which resident the house is showing (ui-structures.md D: the subject
// dropdown), kept on this device; and whether someone new is being woken.
const KEY = 'oneiroi.subject';

const read = (): string | null => {
  try {
    return localStorage.getItem(KEY);
  } catch {
    return null;
  }
};

interface SubjectState {
  id: string | null;
  waking: boolean;
  choose: (id: string) => void;
  setWaking: (w: boolean) => void;
}

export const useSubjectChoice = create<SubjectState>((set) => ({
  id: read(),
  waking: false,
  choose: (id) => {
    try {
      localStorage.setItem(KEY, id);
    } catch {
      // kept for this visit
    }
    set({ id, waking: false });
  },
  setWaking: (waking) => set({ waking }),
}));

const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const EASE = 'cubic-bezier(0.2, 0, 0, 1)';

// Waiting on the new view's reads (the witness, 2026-11-23: "fade out the
// current view, let the new view finish loading and then fade in"): it
// rises once nothing has been fetching for a few frames in a row, and
// never later than this, so a slow read cannot hold the ground forever.
const SETTLE_FRAMES = 3;
const LONGEST_WAIT_MS = 4000;

/**
 * A subject switch fades out to the ground, changes under it, waits for
 * the new view to finish loading, then fades in (decided 2026-11-10: it
 * carries the theme swap, so it gets the pause).
 */
export function switchSubject(change: () => void) {
  const root = document.getElementById('root');
  if (!root || reduced()) return change();
  const out = root.animate([{ opacity: 1 }, { opacity: 0 }], { duration: TIMING.out, easing: EASE, fill: 'forwards' });
  out.onfinish = () => {
    change();
    settled(() => {
      out.cancel();
      root.animate([{ opacity: 0 }, { opacity: 1 }], { duration: TIMING.in, easing: EASE });
    });
  };
}

/** Calls `done` once the new view's reads have settled, or the wait runs out. */
export function settled(done: () => void, isFetching: () => number = () => queries.isFetching(), now: () => number = () => performance.now()) {
  const start = now();
  let calm = 0;
  const tick = () => {
    calm = isFetching() > 0 ? 0 : calm + 1;
    if (calm >= SETTLE_FRAMES || now() - start > LONGEST_WAIT_MS) return done();
    requestAnimationFrame(tick);
  };
  // The first frame renders the new subject and starts its reads.
  requestAnimationFrame(tick);
}
