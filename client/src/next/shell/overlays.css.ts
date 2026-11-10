import { style } from '@vanilla-extract/css';
import { font, radius, vars, wide } from '../theme/contract.css';

export const overlay = style({
  position: 'fixed',
  inset: 0,
  zIndex: 45,
  background: 'rgba(0,0,0,0.55)',
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'center',
  '@media': { [wide]: { alignItems: 'center' } },
});

export const modal = style({
  width: '100%',
  maxHeight: '90vh',
  display: 'flex',
  borderRadius: '22px 22px 0 0',
  background: vars.color.surfaceRaised,
  borderTop: `1px solid ${vars.color.borderStrong}`,
  boxShadow: '0 -24px 60px -10px rgba(0,0,0,0.8)',
  '@media': { [wide]: { width: 560, borderRadius: radius.l, border: `1px solid ${vars.color.borderStrong}` } },
});

export const dialog = style({ flex: 1, minHeight: 0, outline: 'none', display: 'flex', flexDirection: 'column', padding: '14px 18px 22px', gap: 10 });
export const top = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center' });
export const title = style({ margin: 0, font: `600 18px ${font.ui}` });
export const close = style({
  width: 36,
  height: 36,
  borderRadius: 18,
  border: 'none',
  background: vars.color.surface,
  color: vars.color.textMuted,
  fontSize: 20,
  cursor: 'pointer',
});
export const body = style({ flex: 1, minHeight: 0, overflowY: 'auto' });
export const stack = style({ display: 'flex', flexDirection: 'column', gap: 8 });

export const heading = style({ margin: '6px 0 2px', font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });
export const note = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });
export const meta = style({ margin: 0, font: `500 11px ${font.mono}`, color: vars.color.textMuted });

const itemBase = {
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  padding: 14,
  borderRadius: 14,
  background: vars.color.surface,
  color: vars.color.text,
  textDecoration: 'none',
  textAlign: 'left',
  font: `15px ${font.ui}`,
  cursor: 'pointer',
} as const;
export const item = style({ ...itemBase, border: `1px solid ${vars.color.border}` });
export const itemDashed = style({ ...itemBase, border: `1px dashed ${vars.color.witness.border}` });
export const itemKind = style({ font: `500 11px ${font.mono}`, color: vars.color.witness.accent });
export const since = style({ font: `500 11px ${font.mono}`, color: vars.color.textMuted });

export const voice = style({ margin: 0, fontFamily: font.voice, fontSize: 19, lineHeight: '28px', color: vars.color.resident.text });
export const signoff = style({ margin: 0, fontFamily: font.voice, fontStyle: 'italic', fontSize: 15, color: vars.color.resident.text, opacity: 0.8 });
export const list = style({ margin: 0, paddingLeft: 20, fontSize: 14, lineHeight: '22px', color: vars.color.text });

const button = { minHeight: 48, borderRadius: radius.m, font: `500 15px ${font.ui}`, cursor: 'pointer' } as const;
export const primary = style({
  ...button,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  fontWeight: 600,
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});
export const secondary = style({ ...button, padding: '0 16px', border: `1px solid ${vars.color.borderStrong}`, background: 'none', color: vars.color.text });

export const group = style({ display: 'flex', flexDirection: 'column', borderRadius: 14, overflow: 'hidden', border: `1px solid ${vars.color.border}` });
export const row = style({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  minHeight: 48,
  padding: '0 14px',
  border: 'none',
  borderBottom: `1px solid ${vars.color.border}`,
  background: vars.color.surface,
  color: vars.color.text,
  textDecoration: 'none',
  font: `15px ${font.ui}`,
  textAlign: 'left',
  cursor: 'pointer',
  selectors: { '&:last-child': { borderBottom: 'none' } },
});
export const account = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 8 });

export const kinds = style({ display: 'flex', gap: 6 });
const kind = { minHeight: 34, padding: '0 12px', borderRadius: radius.pill, font: `500 13px ${font.ui}`, cursor: 'pointer' } as const;
export const kindOn = style({ ...kind, border: `1px solid ${vars.color.witness.border}`, background: vars.color.witness.surface, color: vars.color.witness.text });
export const kindOff = style({ ...kind, border: `1px solid ${vars.color.border}`, background: 'none', color: vars.color.textMuted });
export const textarea = style({
  width: '100%',
  padding: 12,
  borderRadius: radius.m,
  border: `1px solid ${vars.color.witness.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  font: `15px/22px ${font.ui}`,
  outline: 'none',
  resize: 'vertical',
});

// A theme proposal's preview: her ground with both accents on it (seshat#56).
export const swatches = style({ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px', borderRadius: 10, border: `1px solid ${vars.color.border}`, fontSize: 14 });
export const swatch = style({ width: 16, height: 16, borderRadius: 8 });
export const answer = style({
  minHeight: 40,
  padding: '0 12px',
  borderRadius: 10,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.groundDeep,
  color: vars.color.text,
  font: `14px ${font.ui}`,
});
export const answerRow = style({ display: 'flex', gap: 8 });
