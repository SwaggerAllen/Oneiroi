import { describe, expect, it } from 'vitest';
import { linkCitations, parseCite } from './cite';

describe('citations', () => {
  it('turns a citation into a cite link and parses it back', () => {
    const out = linkCitations('Written in a round — lily:document/etymologies/oneiric.md, and lily:bookmark/360.');
    expect(out).toBe(
      'Written in a round — [document/etymologies/oneiric.md](cite:lily:document/etymologies/oneiric.md), and [bookmark/360](cite:lily:bookmark/360).',
    );
    expect(parseCite('cite:lily:bookmark/360')).toEqual({ slug: 'lily', kind: 'bookmark', ref: '360' });
  });

  it('leaves code alone', () => {
    expect(linkCitations('run `lily:bookmark/1` as is')).toBe('run `lily:bookmark/1` as is');
  });

  it('ignores a URL scheme that is not a citation', () => {
    expect(linkCitations('see https://example.com/doc/1')).toBe('see https://example.com/doc/1');
  });
});
