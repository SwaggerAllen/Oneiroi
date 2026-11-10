// The token contract (theming-notes.md, ui-build.md "Rules every phase
// holds"): roles, never colours. Values arrive at runtime from
// derive(seeds) through assignInlineVars on the shell's root, so a
// subject switch re-themes by swapping variables. A component that names
// a token not in this contract does not compile.

import { createThemeContract, globalStyle } from '@vanilla-extract/css';

const accent = {
  accent: '',
  on: '',
  surface: '',
  surfaceStrong: '',
  border: '',
  borderStrong: '',
  text: '',
  glow: '',
};

export const vars = createThemeContract({
  color: {
    ground: '',
    groundDeep: '',
    surface: '',
    surfaceRaised: '',
    border: '',
    borderStrong: '',
    text: '',
    textMuted: '',
    textFaint: '',
    resident: accent,
    witness: accent,
  },
});

// Unthemed on purpose: signals stay legible on every theme.
export const status = {
  ok: '#6ee7a8',
  warn: '#f5c26b',
  error: '#f28b82',
  warnSurface: '#1d1810',
  warnBorder: '#4a3a1c',
  warnText: '#f3e2bf',
} as const;

export const font = {
  ui: "Inter, system-ui, sans-serif",
  voice: "Newsreader, Georgia, serif",
  mono: "'JetBrains Mono', ui-monospace, monospace",
} as const;

export const space = { 1: '4px', 2: '8px', 3: '12px', 4: '16px', 5: '20px', 6: '24px' } as const;
export const radius = { s: '8px', m: '12px', l: '16px', pill: '999px' } as const;

// One breakpoint (ui-build.md): below it, tabs, sheets and one column;
// above it, the rail, side panels and up to three columns.
export const wide = 'screen and (min-width: 900px)';

globalStyle('html, body, #root', { margin: 0, height: '100%' });
globalStyle('body', {
  background: vars.color.ground,
  color: vars.color.text,
  fontFamily: font.ui,
  WebkitFontSmoothing: 'antialiased',
});
globalStyle('*, *::before, *::after', { boxSizing: 'border-box' });
globalStyle('a', { color: vars.color.witness.accent });
globalStyle(':focus-visible', { outline: `2px solid ${vars.color.witness.accent}`, outlineOffset: '2px' });
