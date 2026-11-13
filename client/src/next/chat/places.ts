// The navigator's places, opened out (the witness, 2026-11-12): her scenes
// and bookmarks over the navigator's range as one list in time order,
// grouped by local day, so a reader can scan them to find a place.

export interface ScenePlace {
  type: 'scene';
  key: string;
  at: string;
  until: string | null;
  anchor: string | null;
  title: string | null;
  summary: string | null;
  mood: string | null;
}

export interface BookmarkPlace {
  type: 'bookmark';
  key: string;
  at: string;
  anchor: string | null;
  number: number;
  line: string | null;
  summary: string | null;
  pinned: boolean;
  private: boolean;
}

export type Place = ScenePlace | BookmarkPlace;

interface SceneRow {
  number: number;
  kind: string;
  title: string | null;
  from_turn: string | null;
  from_time: string | null;
  to_time: string | null;
  summary: string | null;
  mood: string | null;
}

interface BookmarkRow {
  number: number;
  line: string | null;
  summary: string | null;
  private?: boolean;
  anchor_ref: string;
  anchor_at: string;
  pinned_at: string | null;
}

/** Scenes (corrections left out) and bookmarks, oldest first; a scene before a bookmark at the same instant. */
export function places(days: Array<{ scenes: SceneRow[] }>, bookmarks: BookmarkRow[]): Place[] {
  const scenes: Place[] = days.flatMap((d) =>
    d.scenes
      .filter((s) => s.kind === 'scene' && s.from_time)
      .map((s) => ({
        type: 'scene' as const,
        key: `scene:${s.number}`,
        at: s.from_time as string,
        until: s.to_time,
        anchor: s.from_turn,
        title: s.title,
        summary: s.summary,
        mood: s.mood,
      })),
  );
  const marks: Place[] = bookmarks.map((b) => ({
    type: 'bookmark' as const,
    key: `bookmark:${b.number}`,
    at: b.anchor_at,
    anchor: b.private ? null : b.anchor_ref,
    number: b.number,
    line: b.private ? null : b.line,
    summary: b.private ? null : b.summary,
    pinned: b.pinned_at !== null,
    private: b.private === true,
  }));
  return [...scenes, ...marks].sort((a, b) => Date.parse(a.at) - Date.parse(b.at) || (a.type === b.type ? 0 : a.type === 'scene' ? -1 : 1));
}

/** The places grouped by their local day (this browser's zone), in order. */
export function byDay(list: Place[]): Array<{ day: string; places: Place[] }> {
  const out: Array<{ day: string; places: Place[] }> = [];
  for (const p of list) {
    const day = localDay(p.at);
    const last = out[out.length - 1];
    if (last && last.day === day) last.places.push(p);
    else out.push({ day, places: [p] });
  }
  return out;
}

/** YYYY-MM-DD in this browser's zone. */
export function localDay(iso: string): string {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** A `datetime-local` value (this browser's zone) as an ISO instant, or null. */
export function instantOf(local: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(local)) return null;
  const ms = new Date(local).getTime();
  return Number.isNaN(ms) ? null : new Date(ms).toISOString();
}
