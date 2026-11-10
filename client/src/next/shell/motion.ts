import { useLayoutEffect, useRef, useState } from 'react';

// Motion (ui-build.md, theming-notes.md): tabs dissolve, pushes slide,
// reduced motion makes every one instant. The two dissolves are compared
// side by side before one is chosen; until then the choice is a local
// preference (`oneiroi.motion`), set from Settings.

export type Dissolve = 'cross' | 'through';
const KEY = 'oneiroi.motion';

export function dissolve(): Dissolve {
  try {
    return window.localStorage.getItem(KEY) === 'through' ? 'through' : 'cross';
  } catch {
    return 'cross';
  }
}

export function setDissolve(d: Dissolve) {
  try {
    window.localStorage.setItem(KEY, d);
  } catch {
    // A private window: the default stands.
  }
}

export const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const EASE = 'cubic-bezier(0.2, 0, 0, 1)';

/** The timings for one dissolve: a true crossfade, or out to the ground and back in. */
export const TIMING: Record<Dissolve, { out: number; in: number; delay: number }> = {
  cross: { out: 200, in: 200, delay: 0 },
  through: { out: 110, in: 150, delay: 110 },
};

/**
 * Tab switches dissolve. Returns the tab that is leaving (kept visible,
 * inert, while it fades) and a ref setter for each panel.
 */
export function useTabDissolve<T extends string>(tab: T) {
  const panels = useRef(new Map<T, HTMLElement>());
  const prev = useRef(tab);
  const [leaving, setLeaving] = useState<T | null>(null);

  useLayoutEffect(() => {
    const from = prev.current;
    prev.current = tab;
    if (from === tab || reduced()) return;
    const t = TIMING[dissolve()];
    const out = panels.current.get(from);
    const incoming = panels.current.get(tab);
    setLeaving(from);
    incoming?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: t.in, delay: t.delay, easing: EASE, fill: 'backwards' });
    const a = out?.animate([{ opacity: 1 }, { opacity: 0 }], { duration: t.out, easing: EASE, fill: 'forwards' });
    if (!a) return setLeaving(null);
    a.onfinish = () => {
      a.cancel();
      setLeaving((l) => (l === from ? null : l));
    };
  }, [tab]);

  const ref = (t: T) => (el: HTMLElement | null) => {
    if (el) panels.current.set(t, el);
    else panels.current.delete(t);
  };
  return { leaving, ref };
}

/**
 * Pushes slide: deeper comes in from the right, back from the left. The
 * view is not remounted (each tab keeps its state); the arriving content
 * slides a short way in while it fades up.
 */
export function usePushSlide(el: HTMLElement | null, depth: number, enabled: boolean) {
  const prev = useRef(depth);
  useLayoutEffect(() => {
    const from = prev.current;
    prev.current = depth;
    if (!el || !enabled || from === depth || reduced()) return;
    const dx = depth > from ? 28 : -28;
    el.animate(
      [
        { transform: `translateX(${dx}px)`, opacity: 0.4 },
        { transform: 'translateX(0)', opacity: 1 },
      ],
      { duration: 220, easing: EASE },
    );
  }, [el, depth, enabled]);
}
