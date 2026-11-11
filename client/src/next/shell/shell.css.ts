import { keyframes, style, styleVariants } from '@vanilla-extract/css';
import { font, radius, status, vars, wide } from '../theme/contract.css';

// Narrow: header, offline bar, the tab's content, the tab bar.
// Wide: the rail on the left, and the same column to its right.
export const root = style({
  height: '100%',
  display: 'grid',
  gridTemplateColumns: '1fr',
  gridTemplateRows: 'auto auto 1fr auto',
  gridTemplateAreas: '"header" "bar" "main" "tabs"',
  '@media': {
    [wide]: {
      gridTemplateColumns: '72px 1fr',
      gridTemplateRows: 'auto auto 1fr',
      gridTemplateAreas: '"tabs header" "tabs bar" "tabs main"',
    },
  },
});

export const header = style({
  gridArea: 'header',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  padding: '10px 12px 10px 16px',
  minHeight: 64,
});

export const subject = style({
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  minHeight: 44,
  background: 'none',
  border: 'none',
  color: vars.color.text,
  padding: 0,
  font: 'inherit',
  cursor: 'pointer',
});

export const avatar = style({
  position: 'relative',
  width: 30,
  height: 30,
  borderRadius: 15,
  background: vars.color.resident.surfaceStrong,
  boxShadow: `0 0 18px 2px ${vars.color.resident.glow}`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontFamily: font.voice,
  fontSize: 17,
  color: vars.color.resident.text,
  transition: 'box-shadow 300ms ease',
  selectors: { '&[data-working="true"]': { boxShadow: `0 0 26px 6px ${vars.color.resident.glow}` } },
});

export const connectionDot = styleVariants({
  connected: { background: status.ok },
  connecting: { background: status.warn },
  offline: { background: status.error },
});

export const dotBase = style({
  position: 'absolute',
  right: -2,
  bottom: -2,
  width: 10,
  height: 10,
  borderRadius: 5,
  border: `2px solid ${vars.color.ground}`,
});

export const name = style({ fontFamily: font.voice, fontSize: 21, lineHeight: '24px', fontWeight: 500 });

export const presence = style({
  font: `500 10px ${font.mono}`,
  letterSpacing: '0.03em',
  color: vars.color.textFaint,
  textTransform: 'uppercase',
  selectors: { '&[data-working="true"]': { color: vars.color.resident.accent } },
});

export const iconButton = style({
  position: 'relative',
  width: 44,
  height: 44,
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  background: 'none',
  border: 'none',
  color: vars.color.text,
  borderRadius: radius.m,
  cursor: 'pointer',
});

export const badge = style({
  position: 'absolute',
  top: 6,
  right: 5,
  minWidth: 18,
  height: 18,
  padding: '0 4px',
  borderRadius: 9,
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  font: `600 11px ${font.ui}`,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  boxShadow: `0 0 10px ${vars.color.witness.glow}`,
});

export const tabs = style({
  gridArea: 'tabs',
  display: 'flex',
  justifyContent: 'space-around',
  padding: '8px 8px max(10px, env(safe-area-inset-bottom))',
  borderTop: `1px solid ${vars.color.border}`,
  background: vars.color.groundDeep,
  '@media': {
    [wide]: {
      flexDirection: 'column',
      justifyContent: 'flex-start',
      gap: 8,
      padding: '76px 0 16px',
      borderTop: 'none',
      borderRight: `1px solid ${vars.color.border}`,
    },
  },
});

export const tab = style({
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  gap: 4,
  minWidth: 64,
  minHeight: 44,
  background: 'none',
  border: 'none',
  color: vars.color.textMuted,
  font: `500 11px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[aria-current="page"]': { color: vars.color.witness.accent } },
});

export const main = style({ gridArea: 'main', position: 'relative', minHeight: 0, overflow: 'hidden' });

// Every tab stays mounted (ui-structures.md D); only the active one shows.
export const panel = style({
  position: 'absolute',
  inset: 0,
  display: 'flex',
  flexDirection: 'column',
  background: vars.color.ground,
  // Inherited by every tab: a word longer than the screen (a path, a
  // link) breaks rather than pushing the page sideways.
  overflowWrap: 'anywhere',
  selectors: {
    '&[hidden]': { display: 'none' },
    // The leaving tab sits under the arriving one while it fades.
    '&[data-leaving]': { zIndex: 0, pointerEvents: 'none' },
    '&:not([data-leaving])': { zIndex: 1 },
  },
});

export const bar = style({ gridArea: 'bar' });

export const offline = style({
  margin: '0 16px 8px',
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  minHeight: 44,
  padding: '0 6px 0 12px',
  borderRadius: radius.m,
  background: status.warnSurface,
  border: `1px solid ${status.warnBorder}`,
  color: status.warnText,
  fontSize: 13,
});

export const offlineButton = style({
  marginLeft: 'auto',
  minHeight: 34,
  padding: '0 12px',
  borderRadius: 9,
  border: `1px solid ${status.warnBorder}`,
  background: 'transparent',
  color: status.warn,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
});

const pulse = keyframes({ '0%,100%': { opacity: 0.6 }, '50%': { opacity: 1 } });

export const splash = style({
  height: '100%',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  background: vars.color.ground,
});

export const splashMark = style({
  width: 64,
  height: 64,
  borderRadius: 32,
  background: vars.color.resident.surfaceStrong,
  boxShadow: `0 0 50px 8px ${vars.color.resident.glow}`,
  animation: `${pulse} 1.6s ease-in-out infinite`,
  '@media': { '(prefers-reduced-motion: reduce)': { animation: 'none' } },
});

export const empty = style({
  margin: 'auto',
  maxWidth: 320,
  padding: 24,
  textAlign: 'center',
  color: vars.color.textMuted,
  fontSize: 14,
  lineHeight: '21px',
});
