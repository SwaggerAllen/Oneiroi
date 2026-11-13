import { describe, expect, it } from 'vitest';
import type { LibraryDocument } from '../../api/types';
import { leaf, nest } from './nest';

const doc = (path: string, written_at: string) => ({ path, kind: 'research', written_at, created_at: written_at }) as unknown as LibraryDocument;

describe('nest (research passes as folders)', () => {
  const docs = [
    doc('research/17-swallows/task.md', '2026-11-10T10:00:00Z'),
    doc('research/17-swallows/rspb.md', '2026-11-10T09:00:00Z'),
    doc('research/21-ostrom/task.md', '2026-11-12T10:00:00Z'),
    doc('research/21-ostrom/sources/jstor.md', '2026-11-12T09:00:00Z'),
    doc('research/loose.md', '2026-11-11T10:00:00Z'),
  ];

  it('each pass is a folder, newest first; files at the kind’s top stay files', () => {
    const n = nest(docs, 'updated');
    expect(n.folders.map((f) => f.name)).toEqual(['21-ostrom', '17-swallows']);
    expect(n.files.map(leaf)).toEqual(['loose.md']);
    expect(n.folders[1].files.map(leaf)).toEqual(['task.md', 'rspb.md']);
  });

  it('folders nest as deep as the paths go, and carry every document under them', () => {
    const ostrom = nest(docs, 'updated').folders[0];
    expect(ostrom.path).toBe('21-ostrom');
    expect(ostrom.folders.map((f) => f.path)).toEqual(['21-ostrom/sources']);
    expect(ostrom.all).toHaveLength(2);
  });

  it('by name, alphabetically', () => {
    expect(nest(docs, 'name').folders.map((f) => f.name)).toEqual(['17-swallows', '21-ostrom']);
  });
});
