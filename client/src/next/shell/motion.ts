import { useLayoutEffect, useRef, useState } from 'react';

// Motion (ui-build.md, theming-notes.md): tabs dissolve through the
// ground, pushes slide, reduced motion makes every one instant. The
// witness chose the fade through the ground over a direct crossfade
// after a side-by-side (2026-11-10): at these lengths the crossfade
// barely registered as a transition.

export const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const EASE = 'cubic-bezier(0.2, 0, 0, 1)';

/** Out to the ground, then in. */
const TIMING = { out: 110, in: 150 };

/**
 * Tab switches fade out to the ground, then in. Returns the tab that is leaving (kept visible,
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
    const out = panels.current.get(from);
    const incoming = panels.current.get(tab);
    setLeaving(from);
    incoming?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: TIMING.in, delay: TIMING.out, easing: EASE, fill: 'backwards' });
    const a = out?.animate([{ opacity: 1 }, { opacity: 0 }], { duration: TIMING.out, easing: EASE, fill: 'forwards' });
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
