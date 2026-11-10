import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { useNow } from '../shell/presence';
import * as css from './navigator.css';

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

  return (
    <nav className={css.track} aria-label="Navigator: the last two weeks">
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
                    onClick={() => onJump(s.from_turn as string)}
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
            aria-label={`Bookmark ${b.number}: ${b.line}`}
            title={`#${b.number} ${b.line}`}
            onClick={() => onJump(b.anchor_ref)}
          />
        );
      })}
      {place !== null && <span className={css.ring} style={{ top: `${place}%` }} aria-label="Where you are" role="img" />}
    </nav>
  );
}
