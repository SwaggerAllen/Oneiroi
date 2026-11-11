import { describe, expect, it } from 'vitest';
import { contrast, hexToOklch, oklchToHex } from './color';
import { DEFAULT_SEEDS, derive, type Seeds } from './derive';

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

// The server runs the same checks before it writes THEME.md or files her
// proposal (seshat#56). This writes what derive() answers for a spread of
// seed sets to a fixture the server's test reads and must agree with
// (test/oneiroi/seshat/palette_test.exs): a change to the derivation
// fails here until the snapshot is updated (vitest -u), and then fails
// there until the Elixir port follows.
const AGREEMENT: Seeds[] = [
  DEFAULT_SEEDS,
  { ...DEFAULT_SEEDS, witness: '#d4b0fa' },
  { ...DEFAULT_SEEDS, ground: '#8a8a8a' },
  { ...DEFAULT_SEEDS, ground: '#f5f5f0' },
  { ...DEFAULT_SEEDS, resident: '#4b2a7a' },
  { ...DEFAULT_SEEDS, witness: '#1f4e79' },
  { ...DEFAULT_SEEDS, resident: '#fff0f5' },
  { ground: '#101820', resident: '#ffb86b', witness: '#6be3ff' },
  { ground: '#000000', resident: '#ff5c8a', witness: '#5cff9d' },
  { ground: '#1a1a2e', resident: '#e94560', witness: '#f0a500' },
  { ground: '#0b1d13', resident: '#a3e635', witness: '#c084fc' },
  { ground: '#202020', resident: '#ff0000', witness: '#ff3300' },
  { ground: '#2b1d0e', resident: '#ffd27f', witness: '#8fd3ff' },
  { ground: '#3a0ca3', resident: '#f72585', witness: '#4cc9f0' },
  { ground: '#121212', resident: '#bb86fc', witness: '#03dac6' },
  { ground: '#0d0d0d', resident: '#7ee7f5', witness: '#d8b4fe' },
];

describe('the server agrees', () => {
  it('writes the fixture the server reads', async () => {
    const rows = AGREEMENT.map((seeds) => {
      const { tokens, checks, ok } = derive(seeds);
      return { seeds, ok, checks: checks.map(({ name, passed, value }) => ({ name, passed, value })), tokens };
    });
    await expect(`${JSON.stringify(rows, null, 2)}\n`).toMatchFileSnapshot(
      '../../../../test/fixtures/theme/derive.json',
    );
  });
});
