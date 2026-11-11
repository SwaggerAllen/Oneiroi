import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

export const row = style({ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 6 });

const pill = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 4,
  minHeight: 26,
  padding: '0 9px',
  borderRadius: radius.pill,
  font: `500 12px ${font.ui}`,
} as const;

export const mine = style({ ...pill, background: vars.color.witness.surface, color: vars.color.witness.text, border: `1px solid ${vars.color.witness.border}` });
export const hers = style({ ...pill, background: vars.color.resident.surface, color: vars.color.resident.text, border: `1px solid ${vars.color.resident.border}` });

export const add = style({
  minHeight: 32,
  padding: '0 8px',
  border: 'none',
  background: 'none',
  color: vars.color.textMuted,
  font: `500 12px ${font.ui}`,
  cursor: 'pointer',
  borderRadius: radius.s,
});

export const popover = style({
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.borderStrong}`,
  borderRadius: radius.m,
  boxShadow: '0 16px 40px -10px rgba(0,0,0,0.8)',
  padding: 4,
  minWidth: 200,
});

export const menu = style({ outline: 'none', display: 'flex', flexDirection: 'column' });

export const item = style({
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  minHeight: 40,
  padding: '0 10px',
  borderRadius: radius.s,
  color: vars.color.text,
  fontSize: 14,
  outline: 'none',
  cursor: 'pointer',
  selectors: { '&[data-focused]': { background: vars.color.surface } },
});

export const emoji = style({ fontSize: 18, width: 22, textAlign: 'center' });
