import { describe, expect, it } from 'vitest';
import { byDay, instantOf, localDay, places } from './places';

const scene = (number: number, from_time: string, kind = 'scene') => ({
  number,
  kind,
  title: `scene ${number}`,
  from_turn: `t${number}`,
  from_time,
  to_time: null,
  summary: 's',
  mood: null,
});
const mark = (number: number, anchor_at: string, more: object = {}) => ({
  number,
  line: `line ${number}`,
  summary: null,
  anchor_ref: `r${number}`,
  anchor_at,
  pinned_at: null,
  ...more,
});

describe('places (the navigator opened out)', () => {
  it('merges scenes and bookmarks oldest first, corrections left out, a scene first at a tie', () => {
    const list = places(
      [{ scenes: [scene(2, '2026-11-12T10:00:00Z'), scene(3, '2026-11-12T08:00:00Z', 'correction')] }],
      [mark(7, '2026-11-12T11:00:00Z'), mark(5, '2026-11-12T10:00:00Z')],
    );
    expect(list.map((p) => p.key)).toEqual(['scene:2', 'bookmark:5', 'bookmark:7']);
  });

  it('a private bookmark keeps its place and number but no words and no jump', () => {
    const [p] = places([], [mark(4, '2026-11-12T10:00:00Z', { private: true, line: 'secret' })]);
    expect(p).toMatchObject({ type: 'bookmark', number: 4, line: null, anchor: null, private: true });
  });

  it('groups by the local day', () => {
    const a = new Date(2026, 10, 12, 9).toISOString();
    const b = new Date(2026, 10, 12, 23).toISOString();
    const c = new Date(2026, 10, 13, 1).toISOString();
    const groups = byDay(places([], [mark(1, a), mark(2, b), mark(3, c)]));
    expect(groups.map((g) => [g.day, g.places.length])).toEqual([
      ['2026-11-12', 2],
      ['2026-11-13', 1],
    ]);
    expect(localDay(c)).toBe('2026-11-13');
  });

  it('a datetime-local value is the instant in this zone', () => {
    expect(instantOf('2026-11-12T13:45')).toBe(new Date(2026, 10, 12, 13, 45).toISOString());
    expect(instantOf('')).toBeNull();
  });
});
