import { create } from 'zustand';

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

/**
 * A subject switch fades out to the ground, loads, and fades in (decided
 * 2026-11-10: it carries the theme swap, so it gets the pause).
 */
export function switchSubject(change: () => void) {
  const root = document.getElementById('root');
  if (!root || reduced()) return change();
  const out = root.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 160, easing: 'cubic-bezier(0.2, 0, 0, 1)', fill: 'forwards' });
  out.onfinish = () => {
    change();
    // Two frames: the new subject renders under the ground, then rises.
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        out.cancel();
        root.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 240, easing: 'cubic-bezier(0.2, 0, 0, 1)' });
      }),
    );
  };
}
