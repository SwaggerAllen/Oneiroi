import { describe, expect, it } from 'vitest';
import type { LibraryDocument } from '../../api/types';
import { folderKey, sortDocs } from './sort';

const doc = (path: string, written_at: string | null, created_at: string | null = written_at): LibraryDocument => ({
  path,
  kind: path.split('/')[0],
  title: null,
  status: null,
  bytes: null,
  versions: 1,
  written_at,
  created_at,
  written_by: null,
  missing_at: null,
  note: null,
});

const old = doc('writing/a.md', '2026-11-01T10:00:00Z', '2026-10-20T10:00:00Z');
const fresh = doc('writing/b.md', '2026-11-11T10:00:00Z', '2026-11-01T09:00:00Z');
const mid = doc('writing/c.md', '2026-11-05T10:00:00Z', '2026-11-05T10:00:00Z');
const undated = doc('writing/0.md', null);

describe('records order', () => {
  it('puts the last written first by default, undated last', () => {
    expect(sortDocs([old, fresh, undated, mid], 'updated').map((d) => d.path)).toEqual(['writing/b.md', 'writing/c.md', 'writing/a.md', 'writing/0.md']);
  });

  it('reverses for least recently updated, and orders by when each came in for newest added', () => {
    expect(sortDocs([old, fresh, mid], 'updated-oldest').map((d) => d.path)).toEqual(['writing/a.md', 'writing/c.md', 'writing/b.md']);
    expect(sortDocs([old, fresh, mid], 'added').map((d) => d.path)).toEqual(['writing/c.md', 'writing/b.md', 'writing/a.md']);
    expect(sortDocs([mid, fresh, old], 'name').map((d) => d.path)).toEqual(['writing/a.md', 'writing/b.md', 'writing/c.md']);
  });

  it('places a folder by its newest change', () => {
    expect(folderKey([old, fresh], 'updated')).toBe(new Date('2026-11-11T10:00:00Z').getTime());
    expect(folderKey([old, fresh], 'updated-oldest')).toBe(new Date('2026-11-01T10:00:00Z').getTime());
  });
});
