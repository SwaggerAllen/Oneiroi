import { describe, expect, it } from 'vitest';
import { hrefOf, pieces } from './paths';

describe('paths in an ask (brain#90)', () => {
  it('finds files and folders and leaves the rest as text', () => {
    const p = pieces('Read design/p23-r1-domains-per-message.md, then human-correspondence/ and say yes/no.');
    expect(p.filter((x) => 'path' in x).map((x) => ('path' in x ? x.path : ''))).toEqual(['design/p23-r1-domains-per-message.md', 'human-correspondence/']);
    expect(p.map((x) => ('path' in x ? x.path : x.text)).join('')).toBe('Read design/p23-r1-domains-per-message.md, then human-correspondence/ and say yes/no.');
  });

  it('a URL is not a path', () => {
    expect(pieces('see https://example.org/a/b.md').filter((x) => 'path' in x)).toEqual([]);
  });

  it('a file opens in the viewer, a folder in the tree', () => {
    expect(hrefOf('scratch/creation-gift-guidance.md')).toBe('#/records/doc/scratch/creation-gift-guidance.md');
    expect(hrefOf('human-correspondence/')).toBe('#/records/dir/human-correspondence');
  });
});
