import { useQuery } from '@tanstack/react-query';
import { useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import { useNow } from '../shell/presence';
import * as css from './navigator.css';
import { byDay, instantOf, places, type Place } from './places';

const DAYS = 14;
const DAY_MS = 86_400_000;

const iso = (ms: number) => new Date(ms).toISOString().slice(0, 10);

/**
 * The navigator (ui-structures.md D; the canvas's Nocturne scrubber): the
 * last two weeks top to bottom, her scenes as bands, her bookmarks as
 * points, the reader's place as a ring. A day whose scene pass did not
 * finish is marked as such (Lily, letter #509: a short pass must never
 * read as a short day). A band or point jumps the conversation there.
 * Search is the one global search, not a drawer here (decided).
 *
 * Opened out (the witness, 2026-11-12): a point or band also opens the
 * places as words, her scenes with their summaries and her bookmarks with
 * their lines, in time order and focused on the one chosen, to scan for a
 * place; and a day and time at the top jumps there (kumbukumbu#68).
 */
export function Navigator({
  residentId,
  placeAt,
  onJump,
}: {
  residentId: string;
  placeAt: string | null;
  onJump: (anchor: string) => void;
}) {
  const now = useNow(false);
  const end = now;
  const start = end - DAYS * DAY_MS;
  const from = iso(start);
  const to = iso(end);
  const scenes = useQuery({ queryKey: ['resident', residentId, 'chat', 'scenes', from], queryFn: () => api.scenes(residentId, from, to) });
  const bookmarks = useQuery({
    queryKey: ['resident', residentId, 'memory', 'bookmarks-range', from],
    queryFn: () => api.bookmarksPage(residentId, { from, limit: 500 }),
  });

  const y = (t: string | null) => {
    if (!t) return null;
    const ms = Date.parse(t);
    if (Number.isNaN(ms) || ms < start) return null;
    return Math.min(100, ((ms - start) / (end - start)) * 100);
  };
  const place = y(placeAt);
  const [opened, setOpened] = useState<string | null>(null);
  const choose = (key: string, anchor: string) => {
    onJump(anchor);
    setOpened(key);
  };

  return (
    <nav className={css.track} aria-label="Navigator: the last two weeks">
      <button type="button" className={css.open} aria-label="Open the places: scenes and bookmarks as words" aria-expanded={opened !== null} onClick={() => setOpened((o) => (o === null ? '' : null))}>
        ≡
      </button>
      <span className={css.rail} aria-hidden />
      {Array.from({ length: DAYS }, (_, i) => (
        <span key={i} className={css.tick} style={{ top: `${(i / DAYS) * 100}%` }} aria-hidden />
      ))}
      {(scenes.data?.days ?? []).map((d) => {
        const unfinished = !d.complete;
        return (
          <span key={d.day}>
            {d.scenes
              .filter((s) => s.kind === 'scene')
              .map((s) => {
                const top = y(s.from_time);
                const bottom = y(s.to_time) ?? top;
                if (top === null || bottom === null || !s.from_turn) return null;
                return (
                  <button
                    key={s.number}
                    type="button"
                    className={css.band}
                    style={{ top: `${top}%`, height: `max(10px, ${bottom - top}%)` }}
                    aria-label={`Scene: ${s.title ?? 'untitled'}${s.mood ? `, ${s.mood}` : ''}`}
                    title={`${s.title ?? ''}${s.mood ? ` · ${s.mood}` : ''}`}
                    onClick={() => choose(`scene:${s.number}`, s.from_turn as string)}
                  />
                );
              })}
            {unfinished && (
              <span
                className={css.unfinished}
                style={{ top: `${y(`${d.day}T12:00:00`) ?? 0}%` }}
                title={`${d.day}: the scene pass did not finish`}
                aria-label={`${d.day}: scenes not finished`}
                role="img"
              />
            )}
          </span>
        );
      })}
      {(bookmarks.data?.bookmarks ?? []).map((b) => {
        const top = y(b.anchor_at);
        if (top === null) return null;
        return (
          <button
            key={b.number}
            type="button"
            className={b.pinned_at ? css.pin : css.point}
            style={{ top: `${top}%` }}
            aria-label={b.private ? `Bookmark ${b.number}, in a private session` : `Bookmark ${b.number}: ${b.line}`}
            title={b.private ? `#${b.number} · in a private session` : `#${b.number} ${b.line}`}
            onClick={() => !b.private && choose(`bookmark:${b.number}`, b.anchor_ref)}
            disabled={b.private}
          />
        );
      })}
      {place !== null && <span className={css.ring} style={{ top: `${place}%` }} aria-label="Where you are" role="img" />}
      {opened !== null && (
        <Places
          list={places(scenes.data?.days ?? [], bookmarks.data?.bookmarks ?? [])}
          current={opened}
          onJump={(p) => {
            if (p.anchor) choose(p.key, p.anchor);
          }}
          onJumpTo={(instant) => onJump(instant)}
          onClose={() => setOpened(null)}
        />
      )}
    </nav>
  );
}

/** The places as words, focused on the one chosen, with a day-and-time jump at the top. */
function Places({
  list,
  current,
  onJump,
  onJumpTo,
  onClose,
}: {
  list: Place[];
  current: string;
  onJump: (p: Place) => void;
  onJumpTo: (instant: string) => void;
  onClose: () => void;
}) {
  const [when, setWhen] = useState('');
  const groups = useMemo(() => byDay(list), [list]);
  const box = useRef<HTMLDivElement>(null);

  // Focus where the reader chose; with nothing chosen, the newest.
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const node = current ? el.querySelector<HTMLElement>(`[data-key="${CSS.escape(current)}"]`) : null;
    if (node) node.scrollIntoView({ block: 'center' });
    else el.scrollTop = el.scrollHeight;
  }, [current, groups.length]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const instant = instantOf(when);
  const time = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });

  return (
    <section className={css.panel} aria-label="Places: scenes and bookmarks">
      <div className={css.panelHead}>
        <div className={css.panelRow}>
          <h2 className={css.panelTitle}>Places</h2>
          <button type="button" className={css.close} aria-label="Close the places" onClick={onClose}>
            ×
          </button>
        </div>
        <form
          className={css.panelRow}
          onSubmit={(e) => {
            e.preventDefault();
            if (instant) onJumpTo(instant);
          }}
        >
          <input type="datetime-local" className={css.when} value={when} onChange={(e) => setWhen(e.target.value)} aria-label="Go to a day and time" />
          <button type="submit" className={css.go} disabled={!instant}>
            Go
          </button>
        </form>
      </div>
      <div className={css.list} ref={box}>
        {groups.length === 0 && <p className={css.empty}>No scenes or bookmarks in the last two weeks.</p>}
        {groups.map((g) => (
          <div key={g.day} style={{ display: 'contents' }}>
            <p className={css.day}>{g.day}</p>
            {g.places.map((p) => (
              <button
                key={p.key}
                type="button"
                className={css.item}
                data-key={p.key}
                data-current={p.key === current}
                disabled={!p.anchor}
                onClick={() => onJump(p)}
              >
                {p.type === 'scene' ? (
                  <>
                    <span className={css.itemMeta}>
                      Scene · {time(p.at)}
                      {p.until ? `–${time(p.until)}` : ''}
                      {p.mood ? ` · ${p.mood}` : ''}
                    </span>
                    <span className={css.itemText}>{p.title ?? 'Untitled scene'}</span>
                    {p.summary && <span className={css.itemSummary}>{p.summary}</span>}
                  </>
                ) : (
                  <>
                    <span className={css.itemMeta}>
                      {p.pinned ? '★ ' : ''}#{p.number} · {time(p.at)}
                    </span>
                    <span className={css.itemText}>{p.private ? 'In a private session' : p.line}</span>
                    {p.summary && <span className={css.itemSummary}>{p.summary}</span>}
                  </>
                )}
              </button>
            ))}
          </div>
        ))}
      </div>
    </section>
  );
}
