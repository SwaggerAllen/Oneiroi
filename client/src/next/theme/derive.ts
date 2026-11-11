// Three seeds in, every colour token out (theming-notes.md): a ground,
// the resident's colour and the witness's. Nothing in a component names
// a colour; it names a role, and the role's value comes from here. The
// checks are what keep a proposed theme readable: they run on every
// derivation, and a failing set is answered with what failed.

import { contrast, hexToOklch, hueDistance, oklchToHex, withAlpha, type Oklch } from './color';

export interface Seeds {
  ground: string;
  resident: string;
  witness: string;
}

// The decided look's seeds (ui-structures.md, "The look").
export const DEFAULT_SEEDS: Seeds = { ground: '#0a0a10', resident: '#d8b4fe', witness: '#7ee7f5' };

export interface AccentTokens {
  accent: string;
  on: string; // text on a solid accent
  surface: string;
  surfaceStrong: string;
  border: string;
  borderStrong: string;
  text: string; // chip and label text in the accent's family
  glow: string;
}

export interface Tokens {
  ground: string;
  groundDeep: string;
  surface: string;
  surfaceRaised: string;
  border: string;
  borderStrong: string;
  text: string;
  textMuted: string;
  textFaint: string;
  resident: AccentTokens;
  witness: AccentTokens;
}

export interface Check {
  name: string;
  passed: boolean;
  value: number;
  needs: string;
}

export interface Derived {
  tokens: Tokens;
  checks: Check[];
  ok: boolean;
}

const at = (base: Oklch, l: number, c: number): string => oklchToHex({ l, c, h: base.h });

function accent(seed: string): AccentTokens {
  const o = hexToOklch(seed);
  return {
    accent: seed,
    on: at(o, 0.24, Math.min(o.c, 0.06)),
    surface: at(o, 0.2, Math.min(o.c * 0.45, 0.04)),
    surfaceStrong: at(o, 0.24, Math.min(o.c * 0.55, 0.05)),
    border: at(o, 0.31, Math.min(o.c * 0.6, 0.06)),
    borderStrong: at(o, 0.38, Math.min(o.c * 0.75, 0.08)),
    text: at(o, 0.87, Math.min(o.c * 0.75, 0.09)),
    glow: withAlpha(seed, 0.35),
  };
}

export function derive(seeds: Seeds): Derived {
  const g = hexToOklch(seeds.ground);
  const tint = Math.min(g.c, 0.02);
  const tokens: Tokens = {
    ground: seeds.ground,
    groundDeep: at(g, Math.max(g.l - 0.03, 0), tint),
    surface: at(g, g.l + 0.06, tint),
    surfaceRaised: at(g, g.l + 0.08, tint),
    border: at(g, g.l + 0.12, tint + 0.005),
    borderStrong: at(g, g.l + 0.17, tint + 0.01),
    text: at(g, 0.94, 0.01),
    textMuted: at(g, 0.66, 0.02),
    textFaint: at(g, 0.52, 0.02),
    resident: accent(seeds.resident),
    witness: accent(seeds.witness),
  };

  const r = hexToOklch(seeds.resident);
  const w = hexToOklch(seeds.witness);
  const checks: Check[] = [
    check('text on ground', contrast(tokens.text, tokens.ground), 7, '≥ 7:1'),
    check('muted text on ground', contrast(tokens.textMuted, tokens.ground), 4.5, '≥ 4.5:1'),
    check('faint text on surface', contrast(tokens.textFaint, tokens.surface), 3, '≥ 3:1'),
    check('her colour on ground', contrast(seeds.resident, tokens.ground), 4.5, '≥ 4.5:1'),
    check('his colour on ground', contrast(seeds.witness, tokens.ground), 4.5, '≥ 4.5:1'),
    check('text on his colour', contrast(tokens.witness.on, seeds.witness), 4.5, '≥ 4.5:1'),
    // Who said what is told by colour: the two must stay apart in hue or
    // in lightness, which also keeps them apart for most colour blindness.
    check(
      'her colour apart from his',
      Math.max(hueDistance(r.h, w.h) / 60, Math.abs(r.l - w.l) / 0.15),
      1,
      '≥ 60° of hue or 0.15 of lightness',
    ),
  ];
  return { tokens, checks, ok: checks.every((c) => c.passed) };
}

function check(name: string, value: number, min: number, needs: string): Check {
  return { name, passed: value >= min, value: Math.round(value * 100) / 100, needs };
}
