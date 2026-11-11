import { describe, expect, it } from 'vitest';
import { documentPath, linkCitations, parseCite, targetsFor } from './cite';

describe('citations', () => {
  it('links her own citations and parses them back', () => {
    const out = linkCitations('Written in a round — lily:etymologies/oneiric, and lily:bookmark/360.', 'lily');
    expect(out).toBe(
      'Written in a round — [etymologies/oneiric](cite:lily:etymologies/oneiric), and [bookmark/360](cite:lily:bookmark/360).',
    );
    expect(parseCite('cite:lily:bookmark/360')).toEqual({ slug: 'lily', kind: 'bookmark', ref: '360' });
  });

  it('leaves code, URLs and other words alone', () => {
    expect(linkCitations('run `lily:bookmark/1` as is', 'lily')).toBe('run `lily:bookmark/1` as is');
    expect(linkCitations('see https://example.com/doc/1', 'lily')).toBe('see https://example.com/doc/1');
    expect(linkCitations('note:see/this', 'lily')).toBe('note:see/this');
  });

  it('maps a shelf citation to its document, and a record kind to none', () => {
    expect(documentPath({ kind: 'etymologies', ref: 'oneiric' })).toBe('etymologies/oneiric.md');
    expect(documentPath({ kind: 'writing', ref: 'notes.txt' })).toBe('writing/notes.txt');
    expect(documentPath({ kind: 'keepsake', ref: 'pocket-andrew' })).toBe('pocket-andrew.md');
    expect(documentPath({ kind: 'bookmark', ref: '360' })).toBeNull();
  });

  it('names a document the ways it can be cited', () => {
    expect(targetsFor('lily', 'etymologies/oneiric.md')).toEqual(['lily:etymologies/oneiric.md', 'lily:etymologies/oneiric']);
  });
});
