import { describe, expect, it } from 'vitest';
import { hexToOklch } from './color';
import { COLUMNS, grid, ROWS } from './grid';

describe("the theme picker's grid", () => {
  it('is twice the system grid each way', () => {
    const g = grid();
    expect(g.length).toBe(ROWS);
    expect(g.every((row) => row.length === COLUMNS)).toBe(true);
    expect([COLUMNS, ROWS]).toEqual([24, 20]);
  });

  it('offers grounds dark enough without black: several rows under the default ground', () => {
    const ground = hexToOklch('#0a0a10').l;
    const dark = grid().filter((row) => hexToOklch(row[5]).l <= ground + 0.08);
    expect(dark.length).toBeGreaterThanOrEqual(3);
    expect(grid()[0][5]).not.toBe('#000000');
  });

  it('every cell is a hex colour', () => {
    expect(grid().flat().every((h) => /^#[0-9a-f]{6}$/i.test(h))).toBe(true);
  });
});
