import { describe, expect, it } from 'vitest';
import { hrefOf, pieces } from './paths';

describe('paths in an ask (brain#90)', () => {
  it('finds files and folders and leaves the rest as text', () => {
    const p = pieces('Read design/p23-r1-domains-per-message.md, then human-correspondence/ and say yes/no.');
    expect(p.filter((x) => 'path' in x).map((x) => ('path' in x ? x.path : ''))).toEqual(['design/p23-r1-domains-per-message.md', 'human-correspondence/']);
    expect(p.map((x) => ('path' in x ? x.path : x.text)).join('')).toBe('Read design/p23-r1-domains-per-message.md, then human-correspondence/ and say yes/no.');
  });

  it('a web address is a link of its own, never read as a repo path', () => {
    const p = pieces('The §0 test: https://github.com/SwaggerAllen/Oneiroi/blob/main/test/zero_test.exs. Then design/x.md');
    expect(p.filter((x) => 'path' in x)).toEqual([
      { path: 'https://github.com/SwaggerAllen/Oneiroi/blob/main/test/zero_test.exs', href: 'https://github.com/SwaggerAllen/Oneiroi/blob/main/test/zero_test.exs', external: true },
      { path: 'design/x.md', href: '#/records/doc/design/x.md' },
    ]);
    expect(p.map((x) => ('path' in x ? x.path : x.text)).join('')).toBe('The §0 test: https://github.com/SwaggerAllen/Oneiroi/blob/main/test/zero_test.exs. Then design/x.md');
  });

  it('a file opens in the viewer, a folder in the tree', () => {
    expect(hrefOf('scratch/creation-gift-guidance.md')).toBe('#/records/doc/scratch/creation-gift-guidance.md');
    expect(hrefOf('human-correspondence/')).toBe('#/records/dir/human-correspondence');
  });
});
