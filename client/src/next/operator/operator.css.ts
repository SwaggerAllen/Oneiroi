import { style } from '@vanilla-extract/css';
import { font, status, vars } from '../theme/contract.css';

// The operator's accent is steel, fixed, never themed: it must not feel
// like the companion app (ui-structures.md D).
const steel = '#9fb3c8';
const steelSurface = '#141a21';
const steelBorder = '#2b3642';

export const root = style({ height: '100%', display: 'flex', flexDirection: 'column', background: '#0b0d10', color: vars.color.text, fontFamily: font.ui });
export const header = style({ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 20px', borderBottom: `1px solid ${steelBorder}` });
export const badge = style({ padding: '3px 8px', borderRadius: 6, background: steelSurface, border: `1px solid ${steelBorder}`, color: steel, font: `600 11px ${font.mono}` });
export const brand = style({ font: `600 16px ${font.ui}` });
export const home = style({ marginLeft: 'auto', color: steel, fontSize: 13, textDecoration: 'none' });
export const tabs = style({ display: 'flex', gap: 4, padding: '10px 16px', borderBottom: `1px solid ${steelBorder}`, overflowX: 'auto' });
export const tab = style({
  minHeight: 36,
  padding: '0 14px',
  borderRadius: 8,
  border: 'none',
  background: 'none',
  color: vars.color.textMuted,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[data-selected]': { background: steelSurface, color: steel } },
});
export const body = style({ flex: 1, minHeight: 0, display: 'flex' });
export const page = style({ display: 'flex', flexDirection: 'column', gap: 14, padding: '16px 16px 32px', maxWidth: 980, width: '100%', margin: '0 auto' });
export const card = style({ display: 'flex', flexDirection: 'column', gap: 8, padding: 16, borderRadius: 12, background: steelSurface, border: `1px solid ${steelBorder}` });
export const heading = style({ margin: 0, font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: steel });
export const row = style({
  display: 'flex',
  justifyContent: 'space-between',
  gap: 12,
  padding: '8px 0',
  borderBottom: `1px solid ${steelBorder}`,
  fontSize: 14,
  alignItems: 'center',
  selectors: { '&[data-late="true"]': { color: status.warn }, '&[data-gone="true"]': { color: vars.color.textMuted } },
});
export const failure = style({ display: 'flex', flexDirection: 'column', gap: 4, padding: '8px 0', borderBottom: `1px solid ${steelBorder}`, fontSize: 13 });
export const mono = style({ font: `500 11px ${font.mono}`, color: vars.color.textMuted });
export const note = style({ margin: 0, fontSize: 13, color: vars.color.textMuted });
export const input = style({ minHeight: 40, padding: '0 12px', borderRadius: 8, border: `1px solid ${steelBorder}`, background: '#0b0d10', color: vars.color.text, font: `14px ${font.ui}` });
export const buttons = style({ display: 'flex', flexWrap: 'wrap', gap: 8 });
export const button = style({
  minHeight: 38,
  padding: '0 14px',
  borderRadius: 8,
  border: `1px solid ${steelBorder}`,
  background: 'none',
  color: steel,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.4, cursor: 'default' } },
});
export const primary = style([button, { background: steel, color: '#0b0d10', borderColor: steel, fontWeight: 600 }]);
export const danger = style([button, { color: status.error, borderColor: status.error }]);
export const filter = style([button, { minHeight: 32, selectors: { '&[aria-pressed="true"]': { background: steel, color: '#0b0d10' } } }]);
export const link = style({ alignSelf: 'flex-start', padding: 0, border: 'none', background: 'none', color: steel, font: `500 14px ${font.ui}`, textAlign: 'left', cursor: 'pointer' });
export const said = style({ margin: 0, fontSize: 13, color: steel });
export const refused = style({ margin: 0, fontSize: 13, color: status.error });
export const field = style({ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0, fontSize: 12, color: vars.color.textMuted });
export const form = style({ display: 'flex', flexDirection: 'column', gap: 10 });
export const grid = style({ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', alignItems: 'end', gap: 10 });
export const inline = style({ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', justifyContent: 'flex-end' });
export const stack = style({ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, overflowWrap: 'anywhere' });
export const code = style({ margin: 0, font: `600 22px ${font.mono}`, color: steel, letterSpacing: '0.04em', overflowWrap: 'anywhere', userSelect: 'all' });
export const clip = style({ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' });
export const detail = style({ display: 'flex', flexDirection: 'column', gap: 8, paddingTop: 6 });
export const reportBody = style({ margin: 0, fontSize: 14, whiteSpace: 'pre-wrap' });
export const logged = style({ margin: 0, paddingLeft: 18, display: 'flex', flexDirection: 'column', gap: 4 });
export const lines = style({ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 2 });
