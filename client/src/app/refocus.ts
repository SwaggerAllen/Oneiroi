import { useEffect, useRef } from 'react';

// Coming back to the page (client #13): a tab shown again, a window
// focused again, the network back, or a page restored from the
// browser's back-forward cache. A phone suspends a backgrounded tab's
// socket and timers, so what the page shows can be minutes old when it
// is looked at again; each screen reads itself again here rather than
// trusting what it held. `handler` gets how long the page was away, in
// milliseconds (0 when it never noticed leaving). Focus and visibility
// usually fire together on return, so returns within a second are one.
export function onRefocus(handler: (awayMs: number) => void, now: () => number = () => Date.now()): () => void {
  let awaySince: number | null = document.visibilityState === 'hidden' ? now() : null;
  let lastReturn = Number.NEGATIVE_INFINITY;

  const leave = () => {
    if (awaySince === null) awaySince = now();
  };

  const back = () => {
    if (document.visibilityState === 'hidden') return;
    const at = now();
    if (at - lastReturn < 1000) return;
    lastReturn = at;
    const away = awaySince === null ? 0 : at - awaySince;
    awaySince = null;
    handler(away);
  };

  const visibility = () => (document.visibilityState === 'hidden' ? leave() : back());
  const restored = (e: PageTransitionEvent) => {
    if (e.persisted) back();
  };

  document.addEventListener('visibilitychange', visibility);
  window.addEventListener('blur', leave);
  window.addEventListener('focus', back);
  window.addEventListener('online', back);
  window.addEventListener('pageshow', restored);
  return () => {
    document.removeEventListener('visibilitychange', visibility);
    window.removeEventListener('blur', leave);
    window.removeEventListener('focus', back);
    window.removeEventListener('online', back);
    window.removeEventListener('pageshow', restored);
  };
}

// The hook: the newest handler runs, registered once.
export function useRefocus(handler: (awayMs: number) => void) {
  const latest = useRef(handler);
  useEffect(() => {
    latest.current = handler;
  });
  useEffect(() => onRefocus((away) => latest.current(away)), []);
}
