import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

export const panel = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  margin: '4px 0 8px',
  padding: '12px 14px',
  borderRadius: radius.l,
  background: vars.color.witness.surface,
  border: `1px solid ${vars.color.witness.border}`,
});
export const top = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center' });
export const heading = style({ font: `500 11px ${font.mono}`, letterSpacing: '0.05em', color: vars.color.witness.accent });
export const close = style({ width: 32, height: 32, borderRadius: 16, border: 'none', background: 'none', color: vars.color.textMuted, fontSize: 18, cursor: 'pointer' });
export const list = style({ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 6 });
export const item = style({
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  fontSize: 14,
  color: vars.color.text,
  selectors: { '&[data-done="true"]': { color: vars.color.textMuted, textDecoration: 'line-through' } },
});
export const tick = style({
  width: 18,
  height: 18,
  borderRadius: 9,
  flex: 'none',
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: `1px solid ${vars.color.witness.border}`,
  color: vars.color.witness.accent,
  fontSize: 11,
});
export const link = style({ padding: 0, border: 'none', background: 'none', color: vars.color.witness.accent, font: `14px ${font.ui}`, textDecoration: 'none', cursor: 'pointer', textAlign: 'left' });
