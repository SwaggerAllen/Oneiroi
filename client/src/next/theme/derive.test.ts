import { describe, expect, it } from 'vitest';
import { contrast, hexToOklch, oklchToHex } from './color';
import { DEFAULT_SEEDS, derive } from './derive';

describe('color', () => {
  it('round-trips through OKLCH', () => {
    for (const hex of ['#0a0a10', '#d8b4fe', '#7ee7f5', '#ffffff', '#000000']) {
      expect(oklchToHex(hexToOklch(hex))).toBe(hex);
    }
  });

  it('measures WCAG contrast', () => {
    expect(contrast('#ffffff', '#000000')).toBeCloseTo(21, 0);
    expect(contrast('#777777', '#777777')).toBeCloseTo(1, 5);
  });
});

describe('derive', () => {
  it('passes every readability check on the decided seeds', () => {
    const { ok, checks } = derive(DEFAULT_SEEDS);
    expect(checks.filter((c) => !c.passed)).toEqual([]);
    expect(ok).toBe(true);
  });

  it('pins the decided palette', () => {
    expect(derive(DEFAULT_SEEDS).tokens).toMatchSnapshot();
  });

  it('refuses a theme whose two colours a reader could confuse', () => {
    const { ok, checks } = derive({ ...DEFAULT_SEEDS, witness: '#d4b0fa' });
    expect(ok).toBe(false);
    expect(checks.find((c) => c.name === 'her colour apart from his')?.passed).toBe(false);
  });

  it('refuses a ground the text cannot be read on', () => {
    expect(derive({ ...DEFAULT_SEEDS, ground: '#8a8a8a' }).ok).toBe(false);
  });
});
