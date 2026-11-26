import { style, styleVariants } from '@vanilla-extract/css';
import { font, radius, status, vars } from '../theme/contract.css';

// The succession's pages (screen:next-succession): the settings page's
// column and cards, with the chips, walls and quotes the mocks carry.

const chipBase = style({
  display: 'inline-flex',
  alignItems: 'center',
  height: 22,
  padding: '0 9px',
  borderRadius: radius.pill,
  fontSize: 12,
  whiteSpace: 'nowrap',
  border: '1px solid transparent',
});

export const chip = styleVariants({
  ok: [chipBase, { color: status.ok, borderColor: 'rgba(110, 231, 168, 0.35)' }],
  wait: [chipBase, { color: status.warn, background: status.warnSurface, borderColor: status.warnBorder }],
  now: [chipBase, { color: vars.color.witness.text, background: vars.color.witness.surface, borderColor: vars.color.witness.border }],
  muted: [chipBase, { color: vars.color.textMuted, background: vars.color.surface, borderColor: vars.color.border }],
  hers: [chipBase, { color: vars.color.resident.text, background: vars.color.resident.surface, borderColor: vars.color.resident.border }],
  stop: [chipBase, { color: status.error, borderColor: 'rgba(242, 139, 130, 0.4)' }],
});

export const chips = style({ display: 'inline-flex', flexWrap: 'wrap', gap: 6 });

export const head = style({ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 8 });

export const dry = style([
  chipBase,
  {
    color: status.warnText,
    background: status.warnSurface,
    borderColor: status.warnBorder,
    font: `600 11px ${font.mono}`,
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
  },
]);

export const row = style({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'baseline',
  flexWrap: 'wrap',
  gap: 10,
  fontSize: 14,
  lineHeight: '20px',
  minWidth: 0,
});

export const stepNo = style({ font: `500 12px ${font.mono}`, color: vars.color.textFaint, marginRight: 8 });

export const now = style({ borderColor: vars.color.witness.border });

export const wall = style({
  display: 'flex',
  gap: 10,
  alignItems: 'flex-start',
  padding: 12,
  borderRadius: 10,
  background: status.warnSurface,
  border: `1px solid ${status.warnBorder}`,
  color: status.warnText,
  fontSize: 13,
  lineHeight: '19px',
});

/** Her own words, or her baseline's: the resident's colour, the voice face. */
export const hers = style({
  margin: 0,
  padding: '10px 12px',
  borderRadius: radius.m,
  background: vars.color.resident.surface,
  border: `1px solid ${vars.color.resident.border}`,
  color: vars.color.resident.text,
  fontFamily: font.voice,
  fontSize: 16,
  lineHeight: '24px',
  whiteSpace: 'pre-wrap',
});

export const run = style({
  margin: 0,
  padding: '10px 12px',
  borderRadius: radius.m,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  fontFamily: font.voice,
  fontSize: 16,
  lineHeight: '24px',
  whiteSpace: 'pre-wrap',
});

export const choice = style({
  minHeight: 44,
  padding: '8px 12px',
  textAlign: 'left',
  borderRadius: 10,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.textMuted,
  font: `500 14px ${font.ui}`,
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
  cursor: 'pointer',
  selectors: {
    '&[aria-pressed="true"]': {
      background: vars.color.witness.surface,
      borderColor: vars.color.witness.border,
      color: vars.color.witness.text,
    },
    '&:disabled': { opacity: 0.45, cursor: 'default' },
  },
});
export const hint = style({ fontSize: 12, fontWeight: 400, color: vars.color.textMuted });

export const post = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 6,
  padding: 14,
  borderRadius: radius.m,
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.border}`,
});
export const passed = style({ color: vars.color.textMuted, fontSize: 14 });

export const banner = style({
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: 10,
  margin: '0 16px 6px',
  padding: '10px 14px',
  borderRadius: radius.m,
  background: vars.color.witness.surface,
  border: `1px solid ${vars.color.witness.border}`,
  color: vars.color.text,
  textAlign: 'left',
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
});
export const bannerLink = style({ fontSize: 12, color: vars.color.witness.text });
export const bannerBody = style({ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 });
/** The state's words and the dry-run mark, which wraps under them on a narrow screen rather than hiding. */
export const bannerHead = style({ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 6 });
export const bannerFoot = style({ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 });
/** What waits on you, a word or two: it gives way first when the line is short of room. */
export const bannerWords = style([
  chipBase,
  {
    color: status.warn,
    background: status.warnSurface,
    borderColor: status.warnBorder,
    display: 'block',
    lineHeight: '20px',
    minWidth: 0,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
]);
/** The room's quiet clock, under the round. */
export const quiet = style({ font: `500 12px ${font.mono}`, color: vars.color.textMuted });

/** The deliberation's own pages fill the panel above its tab bar. */
export const tabbed = style({ display: 'flex', flexDirection: 'column', gap: 12 });

/** The archive's runs of one model, each judge's judgment under the run. */
export const archiveRun = style({ display: 'flex', flexDirection: 'column', gap: 6, paddingTop: 10, borderTop: `1px solid ${vars.color.border}` });
export const archiveJudgment = style({ display: 'flex', flexDirection: 'column', gap: 4, paddingLeft: 10, borderLeft: `2px solid ${vars.color.border}` });
