import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

export const track = style({ position: 'relative', width: 28, flex: 'none', margin: '12px 4px 12px 0' });
export const rail = style({ position: 'absolute', top: 0, bottom: 0, left: 13, width: 2, borderRadius: 1, background: vars.color.border });
export const tick = style({ position: 'absolute', left: 6, width: 16, height: 1, background: vars.color.border, opacity: 0.6 });

export const band = style({
  position: 'absolute',
  left: 9,
  width: 10,
  padding: 0,
  border: 'none',
  borderRadius: 5,
  background: vars.color.resident.surfaceStrong,
  boxShadow: `0 0 12px ${vars.color.resident.glow}`,
  cursor: 'pointer',
  selectors: { '&:hover, &:focus-visible': { background: vars.color.resident.border } },
});

const dot = {
  position: 'absolute',
  padding: 0,
  border: 'none',
  borderRadius: '50%',
  cursor: 'pointer',
  transform: 'translateY(-50%)',
} as const;
export const point = style({ ...dot, left: 11, width: 6, height: 6, background: vars.color.resident.text, opacity: 0.8 });
export const pin = style({ ...dot, left: 8, width: 12, height: 12, background: vars.color.resident.accent, boxShadow: `0 0 10px ${vars.color.resident.glow}` });

export const unfinished = style({
  position: 'absolute',
  left: 6,
  width: 16,
  height: 16,
  transform: 'translateY(-50%)',
  borderRadius: 4,
  border: `1px dashed ${vars.color.resident.borderStrong}`,
  // A mark, never a target: the scenes under it stay clickable.
  pointerEvents: 'none',
});

export const ring = style({
  position: 'absolute',
  left: 7,
  width: 14,
  height: 14,
  transform: 'translateY(-50%)',
  borderRadius: 7,
  border: `2px solid ${vars.color.witness.accent}`,
  boxShadow: `0 0 12px ${vars.color.witness.glow}`,
  pointerEvents: 'none',
});

// The navigator opened out (the witness, 2026-11-12): her scenes and
// bookmarks as words, to scan for a place, with a day-and-time jump.
export const open = style({
  position: 'absolute',
  top: 0,
  left: 0,
  width: 28,
  height: 20,
  padding: 0,
  border: 'none',
  background: 'none',
  color: vars.color.textFaint,
  font: `500 12px ${font.ui}`,
  cursor: 'pointer',
  zIndex: 1,
  selectors: { '&:hover, &:focus-visible': { color: vars.color.text } },
});
export const panel = style({
  position: 'absolute',
  top: 0,
  bottom: 0,
  right: 'calc(100% + 4px)',
  width: 'min(360px, calc(100vw - 72px))',
  zIndex: 5,
  display: 'flex',
  flexDirection: 'column',
  borderRadius: radius.l,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.surfaceRaised,
  boxShadow: '0 12px 40px rgba(0,0,0,0.35)',
  overflow: 'hidden',
});
export const panelHead = style({ display: 'flex', flexDirection: 'column', gap: 8, padding: 12, borderBottom: `1px solid ${vars.color.border}` });
export const panelRow = style({ display: 'flex', alignItems: 'center', gap: 8 });
export const panelTitle = style({ flex: 1, margin: 0, font: `600 13px ${font.ui}`, color: vars.color.text });
export const close = style({ minWidth: 32, minHeight: 32, border: 'none', background: 'none', color: vars.color.textMuted, fontSize: 18, cursor: 'pointer' });
export const when = style({
  flex: 1,
  minWidth: 0,
  minHeight: 34,
  padding: '0 8px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  font: `13px ${font.ui}`,
});
export const go = style({
  minHeight: 34,
  padding: '0 12px',
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.witness.border}`,
  background: vars.color.witness.surface,
  color: vars.color.witness.text,
  font: `500 12px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});
export const list = style({ flex: 1, minHeight: 0, overflowY: 'auto', padding: '4px 8px 12px', display: 'flex', flexDirection: 'column', gap: 4 });
export const day = style({ margin: '10px 4px 2px', font: `500 11px ${font.mono}`, letterSpacing: '0.05em', textTransform: 'uppercase', color: vars.color.textFaint });
export const item = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 3,
  width: '100%',
  padding: '8px 10px',
  borderRadius: radius.m,
  border: '1px solid transparent',
  background: 'none',
  textAlign: 'left',
  color: vars.color.text,
  cursor: 'pointer',
  selectors: {
    '&:hover, &:focus-visible': { background: vars.color.surface },
    '&[data-current="true"]': { borderColor: vars.color.resident.borderStrong, background: vars.color.resident.surface },
    '&:disabled': { cursor: 'default', opacity: 0.6 },
  },
});
export const itemMeta = style({ font: `500 11px ${font.mono}`, color: vars.color.resident.text });
export const itemText = style({ fontSize: 13, lineHeight: '19px', overflowWrap: 'anywhere' });
export const itemSummary = style({ fontSize: 12, lineHeight: '18px', color: vars.color.textMuted, overflowWrap: 'anywhere' });
export const empty = style({ margin: 12, fontSize: 13, color: vars.color.textMuted });
