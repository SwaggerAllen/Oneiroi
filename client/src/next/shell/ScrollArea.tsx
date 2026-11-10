import { useEffect, useRef, useState, type ReactNode } from 'react';
import * as css from './scroll.css';

/**
 * The one scroll container (ui-build.md): a short fade at an edge only
 * while there is more past it. The fade is a mask, not an overlay, so
 * taps reach what is under it, and it is gone exactly at each end.
 */
export function ScrollArea({ children, label }: { children: ReactNode; label?: string }) {
  const root = useRef<HTMLDivElement>(null);
  const top = useRef<HTMLDivElement>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ top: false, bottom: false });

  useEffect(() => {
    const container = root.current;
    if (!container || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(
      (entries) =>
        setEdges((e) => {
          const next = { ...e };
          for (const entry of entries) {
            if (entry.target === top.current) next.top = !entry.isIntersecting;
            if (entry.target === bottom.current) next.bottom = !entry.isIntersecting;
          }
          return next;
        }),
      { root: container },
    );
    if (top.current) observer.observe(top.current);
    if (bottom.current) observer.observe(bottom.current);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={root}
      className={css.area}
      data-more-above={edges.top}
      data-more-below={edges.bottom}
      role={label ? 'region' : undefined}
      aria-label={label}
      tabIndex={label ? 0 : undefined}
    >
      <div ref={top} className={css.sentinel} />
      {children}
      <div ref={bottom} className={css.sentinel} />
    </div>
  );
}
