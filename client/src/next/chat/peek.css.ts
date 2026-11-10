import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

export const overlay = style({
  position: 'fixed',
  inset: 0,
  zIndex: 40,
  background: 'rgba(0,0,0,0.5)',
  display: 'flex',
  alignItems: 'flex-end',
});

export const sheet = style({
  width: '100%',
  maxHeight: '78vh',
  display: 'flex',
  borderRadius: '22px 22px 0 0',
  background: vars.color.surfaceRaised,
  borderTop: `1px solid ${vars.color.resident.borderStrong}`,
  boxShadow: `0 -24px 60px -10px rgba(0,0,0,0.8), 0 -2px 40px -18px ${vars.color.resident.glow}`,
});

export const dialog = style({
  flex: 1,
  minHeight: 0,
  outline: 'none',
  padding: '10px 18px 20px',
  display: 'flex',
  flexDirection: 'column',
  gap: 10,
});

export const panel = style({
  width: 400,
  flex: 'none',
  minHeight: 0,
  display: 'flex',
  flexDirection: 'column',
  gap: 10,
  padding: '14px 18px 18px',
  background: vars.color.surface,
  borderLeft: `1px solid ${vars.color.resident.border}`,
  boxShadow: `-12px 0 40px -20px ${vars.color.resident.glow}`,
});

export const grabber = style({ alignSelf: 'center', width: 40, height: 4, borderRadius: 2, background: vars.color.borderStrong });

export const top = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center' });

export const path = style({ font: `500 12px ${font.mono}`, color: vars.color.resident.text, overflowWrap: 'anywhere' });

export const close = style({
  width: 36,
  height: 36,
  flex: 'none',
  borderRadius: 18,
  border: 'none',
  background: vars.color.surfaceRaised,
  color: vars.color.textMuted,
  fontSize: 20,
  cursor: 'pointer',
});

export const title = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 26, color: vars.color.text });

export const body = style({ flex: 1, minHeight: 0, overflowY: 'auto' });

export const note = style({ margin: '0 0 8px', fontSize: 14, color: vars.color.textMuted });
export const line = style({ margin: '0 0 8px', fontFamily: font.voice, fontSize: 18, lineHeight: '26px', color: vars.color.text });
export const meta = style({ margin: 0, font: `500 11px ${font.mono}`, color: vars.color.textFaint });

export const actions = style({ display: 'flex', gap: 8 });

export const primary = style({
  flex: 1,
  minHeight: 46,
  borderRadius: radius.m,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  font: `600 14px ${font.ui}`,
  cursor: 'pointer',
});
