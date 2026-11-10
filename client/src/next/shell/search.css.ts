import { style } from '@vanilla-extract/css';
import { font, radius, vars, wide } from '../theme/contract.css';

export const overlay = style({
  position: 'fixed',
  inset: 0,
  zIndex: 50,
  background: 'rgba(0,0,0,0.55)',
  display: 'flex',
  alignItems: 'flex-end',
  justifyContent: 'center',
  '@media': { [wide]: { alignItems: 'flex-start', paddingTop: '12vh' } },
});

export const modal = style({
  width: '100%',
  maxHeight: '85vh',
  borderRadius: '22px 22px 0 0',
  background: vars.color.surfaceRaised,
  borderTop: `1px solid ${vars.color.borderStrong}`,
  boxShadow: '0 -24px 60px -10px rgba(0,0,0,0.8)',
  '@media': { [wide]: { width: 640, borderRadius: radius.l, border: `1px solid ${vars.color.borderStrong}` } },
});

export const dialog = style({ outline: 'none', padding: 16, display: 'flex', flexDirection: 'column', gap: 12 });

export const field = style({ display: 'flex' });

export const input = style({
  flex: 1,
  minHeight: 46,
  padding: '0 14px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.witness.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  font: `15px ${font.ui}`,
  outline: 'none',
  selectors: { '&:focus': { boxShadow: `0 0 0 3px ${vars.color.witness.glow}` } },
});

export const scopes = style({ display: 'flex', flexWrap: 'wrap', gap: 6 });

export const scope = style({
  minHeight: 32,
  padding: '0 12px',
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.border}`,
  background: 'none',
  color: vars.color.textMuted,
  font: `500 12px ${font.ui}`,
  cursor: 'pointer',
  selectors: {
    '&[data-selected]': {
      background: vars.color.resident.surfaceStrong,
      borderColor: vars.color.resident.borderStrong,
      color: vars.color.resident.text,
    },
  },
});

export const results = style({ display: 'flex', flexDirection: 'column', gap: 8, overflowY: 'auto', maxHeight: '55vh' });

export const note = style({ margin: 0, color: vars.color.textMuted, fontSize: 13 });

export const hit = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  padding: 10,
  borderRadius: 10,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  textDecoration: 'none',
  color: vars.color.text,
});

export const hitPath = style({ font: `500 11px ${font.mono}`, color: vars.color.resident.text });
export const hitText = style({ fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });

export const visuallyHidden = style({
  position: 'absolute',
  width: 1,
  height: 1,
  overflow: 'hidden',
  clip: 'rect(0 0 0 0)',
  whiteSpace: 'nowrap',
});
