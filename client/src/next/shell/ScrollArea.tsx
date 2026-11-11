import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import * as css from './scroll.css';

export interface Edges {
  top: boolean; // more above
  bottom: boolean; // more below
}

/**
 * The one scroll container (ui-build.md): a short fade at an edge only
 * while there is more past it. The fade is a mask, not an overlay, so
 * taps reach what is under it, and it is gone exactly at each end. A
 * screen that drives its own scrolling (Chat) passes `scrollRef` and
 * hears the edges through `onEdges`.
 */
export function ScrollArea({
  children,
  label,
  scrollRef,
  onEdges,
}: {
  children: ReactNode;
  label?: string;
  scrollRef?: RefObject<HTMLDivElement | null>;
  onEdges?: (edges: Edges) => void;
}) {
  const own = useRef<HTMLDivElement>(null);
  const root = scrollRef ?? own;
  const top = useRef<HTMLDivElement>(null);
  const bottom = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState<Edges>({ top: false, bottom: false });
  const report = useRef(onEdges);
  useEffect(() => {
    report.current = onEdges;
  }, [onEdges]);

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
          report.current?.(next);
          return next;
        }),
      { root: container },
    );
    if (top.current) observer.observe(top.current);
    if (bottom.current) observer.observe(bottom.current);
    return () => observer.disconnect();
  }, [root]);

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
