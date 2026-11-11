import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

// The bell's answers in place, and the Mail view (screens/next-mail.md).
export const panel = style({ display: 'flex', flexDirection: 'column', gap: 8, paddingTop: 8, borderTop: `1px solid ${vars.color.border}` });
export const text = style({ margin: 0, fontSize: 14, lineHeight: '21px', color: vars.color.text, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' });
export const meta = style({ margin: 0, font: `500 11px ${font.mono}`, color: vars.color.textMuted, overflowWrap: 'anywhere' });
export const note = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });
export const said = style({ margin: 0, fontSize: 13, color: vars.color.witness.accent });
export const row = style({ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' });
export const input = style({
  minHeight: 40,
  padding: '0 12px',
  borderRadius: 10,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.groundDeep,
  color: vars.color.text,
  font: `14px ${font.ui}`,
  flex: '1 1 180px',
  minWidth: 0,
});
export const area = style({
  padding: 12,
  borderRadius: 10,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.groundDeep,
  color: vars.color.text,
  font: `14px/21px ${font.ui}`,
  resize: 'vertical',
  minHeight: 96,
});
const button = { minHeight: 38, padding: '0 14px', borderRadius: 10, font: `500 13px ${font.ui}`, cursor: 'pointer' } as const;
export const primary = style({
  ...button,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  fontWeight: 600,
  selectors: { '&:disabled': { opacity: 0.45, cursor: 'default' } },
});
export const quiet = style({
  ...button,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.text,
  selectors: { '&:disabled': { opacity: 0.45, cursor: 'default' } },
});
export const link = style({ color: vars.color.witness.accent, fontSize: 13, textDecoration: 'none' });

// Mail
export const page = style({ display: 'flex', flexDirection: 'column', gap: 18, padding: '8px 16px 32px', maxWidth: 760, width: '100%', margin: '0 auto' });
export const heading = style({ margin: '6px 0 0', font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });
export const card = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 6,
  padding: 12,
  borderRadius: radius.m,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  minWidth: 0,
});
export const open = style({ font: `500 11px ${font.mono}`, color: vars.color.witness.accent });
export const closed = style({ font: `500 11px ${font.mono}`, color: vars.color.textMuted });
export const summary = style({ cursor: 'pointer', fontSize: 14, lineHeight: '21px', color: vars.color.text, overflowWrap: 'anywhere' });
export const thread = style({ display: 'flex', flexDirection: 'column', gap: 8, paddingLeft: 10, borderLeft: `2px solid ${vars.color.border}` });
export const hers = style({ borderLeftColor: vars.color.resident.border });
export const segment = style({ display: 'flex', gap: 4 });
export const segmentButton = style({
  minHeight: 32,
  padding: '0 12px',
  borderRadius: 8,
  border: `1px solid ${vars.color.border}`,
  background: 'none',
  color: vars.color.textMuted,
  font: `500 12px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[aria-pressed="true"]': { color: vars.color.text, borderColor: vars.color.borderStrong, background: vars.color.surfaceRaised } },
});
