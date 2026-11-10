import { style } from '@vanilla-extract/css';
import { font, radius, vars, wide } from '../theme/contract.css';

export const tab = style({ flex: 1, minHeight: 0, display: 'flex' });

export const treeColumn = style({
  display: 'none',
  '@media': {
    [wide]: {
      display: 'flex',
      flexDirection: 'column',
      width: 300,
      flex: 'none',
      minHeight: 0,
      borderRight: `1px solid ${vars.color.border}`,
    },
  },
});

export const page = style({ flex: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column' });

export const pad = style({ display: 'flex', flexDirection: 'column', gap: 4, padding: '8px 12px 24px' });

export const heading = style({ margin: '10px 4px 4px', font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });

export const folder = style({
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  minHeight: 44,
  padding: '0 10px',
  borderRadius: 10,
  border: '1px solid transparent',
  background: 'none',
  color: vars.color.text,
  font: `15px ${font.ui}`,
  textAlign: 'left',
  width: '100%',
  cursor: 'pointer',
  selectors: {
    '&[data-hers="true"]': { background: vars.color.resident.surface, borderColor: vars.color.resident.border },
    '&[aria-current="page"]': { borderColor: vars.color.witness.border },
  },
});

export const folderName = style({ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' });
export const badge = style({ flex: 'none', font: `500 10px ${font.mono}`, color: vars.color.textMuted });
export const badgeHers = style([badge, { color: vars.color.resident.text }]);
export const badgeWaits = style([badge, { color: vars.color.witness.accent }]);

export const file = style({
  display: 'flex',
  alignItems: 'center',
  gap: 8,
  minHeight: 38,
  padding: '0 10px 0 40px',
  border: 'none',
  borderRadius: 8,
  background: 'none',
  color: vars.color.text,
  font: `13px ${font.mono}`,
  textAlign: 'left',
  width: '100%',
  cursor: 'pointer',
  selectors: { '&[aria-current="page"]': { background: vars.color.surface, color: vars.color.witness.text } },
});

export const settings = style({
  width: 36,
  height: 36,
  flex: 'none',
  border: 'none',
  borderRadius: 8,
  background: 'none',
  color: vars.color.textMuted,
  cursor: 'pointer',
});

export const back = style({
  alignSelf: 'flex-start',
  minHeight: 40,
  padding: '0 10px',
  border: 'none',
  background: 'none',
  color: vars.color.witness.accent,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
  '@media': { [wide]: { display: 'none' } },
});

export const viewer = style({ display: 'flex', flexDirection: 'column', gap: 12, padding: '4px 20px 32px', maxWidth: 720, width: '100%', margin: '0 auto' });
export const meta = style({ font: `500 11px ${font.mono}`, color: vars.color.textMuted, textTransform: 'uppercase', overflowWrap: 'anywhere' });
export const title = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 32, lineHeight: '38px', color: vars.color.text });

export const bar = style({
  display: 'flex',
  alignItems: 'center',
  gap: 8,
  padding: '9px 12px',
  borderRadius: 10,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  fontSize: 13,
  color: vars.color.textMuted,
});

export const links = style({ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 6 });
export const linksLabel = style({ font: `500 11px ${font.mono}`, color: vars.color.textFaint, marginRight: 4 });
export const chip = style({
  padding: '3px 8px',
  borderRadius: 6,
  border: `1px solid ${vars.color.resident.border}`,
  background: vars.color.resident.surfaceStrong,
  color: vars.color.resident.text,
  font: `500 12px ${font.mono}`,
  cursor: 'pointer',
  selectors: { '&[data-broken="true"]': { opacity: 0.55, textDecoration: 'line-through' } },
});

export const card = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 10,
  padding: 14,
  borderRadius: radius.l,
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.border}`,
});

export const cardHeading = style({ margin: 0, font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });

export const grid = style({ display: 'grid', gridTemplateColumns: '120px 1fr', gap: '8px 10px', fontSize: 14 });
export const label = style({ color: vars.color.textMuted });

export const note = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });

export const emptyPage = style({ margin: 'auto', color: vars.color.textMuted, fontSize: 14 });
