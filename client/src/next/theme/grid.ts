import { oklchToHex } from './color';

// The theme picker's grid (the witness, 2026-11-23): twice the system
// picker's grid each way, 24 columns by 20 rows, so a ground dark enough
// for the readability checks is there without going to black. Column one
// is the greys; the rest are hues around the wheel. Rows run dark to
// light, spaced closer at the dark end, where grounds live.

export const COLUMNS = 24;
export const ROWS = 20;

/** Row `r`'s lightness (OKLCH L), from near black to near white, dense in the darks. */
export const lightness = (r: number) => 0.06 + 0.9 * (r / (ROWS - 1)) ** 1.6;

/** The colour of the cell at column `c`, row `r`. */
export function cell(c: number, r: number): string {
  const l = lightness(r);
  if (c === 0) return oklchToHex({ l, c: 0, h: 0 });
  const h = ((c - 1) * 360) / (COLUMNS - 1);
  // Chroma follows lightness, so the darks stay dark and in gamut.
  const chroma = Math.min(0.16, 0.05 + l * 0.18) * (l > 0.85 ? (1 - l) / 0.15 : 1);
  return oklchToHex({ l, c: chroma, h });
}

/** The whole grid, rows of hexes, dark first. */
export const grid = (): string[][] => Array.from({ length: ROWS }, (_, r) => Array.from({ length: COLUMNS }, (_, c) => cell(c, r)));
