import { style } from '@vanilla-extract/css';
import { font, vars } from '../theme/contract.css';

export const page = style({ display: 'flex', flexDirection: 'column', gap: 18, padding: '12px 16px 24px', maxWidth: 720, margin: '0 auto', width: '100%' });
export const section = style({ display: 'flex', flexDirection: 'column', gap: 6 });
export const heading = style({ margin: '0 0 2px', font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });
export const headingLive = style([heading, { color: vars.color.witness.accent }]);
export const empty = style({ margin: 0, fontSize: 13, color: vars.color.textMuted });

const rowBase = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: 12,
  minHeight: 46,
  padding: '0 12px',
  borderRadius: 10,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  color: vars.color.text,
  fontSize: 15,
} as const;

export const row = style(rowBase);
export const rowButton = style({ ...rowBase, width: '100%', textAlign: 'left', font: `15px ${font.ui}`, cursor: 'pointer' });
export const title = style({ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' });
export const place = style({ color: vars.color.textMuted });
export const when = style({ flex: 'none', font: `500 11px ${font.mono}`, color: vars.color.textMuted });
export const dot = style({ width: 8, height: 8, flex: 'none', borderRadius: 4, background: vars.color.resident.accent, boxShadow: `0 0 10px ${vars.color.resident.accent}` });
