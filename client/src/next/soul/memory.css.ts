import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

// Soul › Memory: the view and tag toggles, and a retrieval target.
export const views = style({ display: 'flex', flexWrap: 'wrap', gap: 6 });
const toggle = {
  minHeight: 36,
  padding: '0 12px',
  borderRadius: radius.pill,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
} as const;
export const view = style({ ...toggle, border: `1px solid ${vars.color.border}`, background: vars.color.surface, color: vars.color.textMuted });
export const viewOn = style({ ...toggle, border: `1px solid ${vars.color.witness.border}`, background: vars.color.witness.surface, color: vars.color.witness.accent });
export const target = style({ font: `500 13px ${font.mono}`, color: vars.color.text, overflowWrap: 'anywhere' });
