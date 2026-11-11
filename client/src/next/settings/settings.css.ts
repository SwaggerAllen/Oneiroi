import { style } from '@vanilla-extract/css';
import { font, radius, status, vars } from '../theme/contract.css';

// A settings page (screens/next-settings.md): one column of cards under a
// back link and a title, in the house's tokens.

export const page = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 14,
  padding: '4px 16px 40px',
  maxWidth: 760,
  width: '100%',
  margin: '0 auto',
});

export const back = style({
  alignSelf: 'flex-start',
  minHeight: 40,
  padding: '0 8px',
  marginLeft: -8,
  border: 'none',
  background: 'none',
  color: vars.color.witness.accent,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
});

export const title = style({
  margin: 0,
  fontFamily: font.voice,
  fontWeight: 500,
  fontSize: 30,
  lineHeight: '36px',
  color: vars.color.text,
});
export const lede = style({
  margin: 0,
  fontSize: 14,
  lineHeight: '21px',
  color: vars.color.textMuted,
});

export const card = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 10,
  padding: 14,
  borderRadius: radius.l,
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.border}`,
  minWidth: 0,
});
export const cardWitness = style([
  card,
  {
    borderColor: vars.color.witness.border,
    boxShadow: `0 0 30px -12px ${vars.color.witness.glow}`,
  },
]);

export const heading = style({
  margin: 0,
  font: `500 11px ${font.mono}`,
  letterSpacing: '0.04em',
  color: vars.color.textFaint,
  textTransform: 'uppercase',
});
export const subheading = style({
  margin: '4px 0 0',
  fontSize: 14,
  fontWeight: 600,
  color: vars.color.text,
});
export const note = style({
  margin: 0,
  fontSize: 13,
  lineHeight: '19px',
  color: vars.color.textMuted,
});
export const meta = style({
  font: `500 11px ${font.mono}`,
  color: vars.color.textMuted,
  overflowWrap: 'anywhere',
});
export const text = style({
  margin: 0,
  fontSize: 15,
  lineHeight: '22px',
  color: vars.color.text,
  overflowWrap: 'anywhere',
});
export const voice = style({
  margin: 0,
  fontFamily: font.voice,
  fontSize: 17,
  lineHeight: '26px',
  color: vars.color.text,
  whiteSpace: 'pre-wrap',
  overflowWrap: 'anywhere',
});
export const mono = style({
  font: `13px ${font.mono}`,
  overflowWrap: 'anywhere',
});
export const warn = style({ color: status.warn });
export const said = style({
  margin: 0,
  fontSize: 14,
  lineHeight: '20px',
  color: vars.color.text,
});
export const refused = style({
  margin: 0,
  padding: '8px 12px',
  borderRadius: 10,
  background: status.warnSurface,
  border: `1px solid ${status.warnBorder}`,
  color: status.warnText,
  fontSize: 14,
  lineHeight: '20px',
});

export const list = style({
  margin: 0,
  padding: 0,
  listStyle: 'none',
  display: 'flex',
  flexDirection: 'column',
});
export const item = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  padding: '10px 0',
  borderTop: `1px solid ${vars.color.border}`,
  minWidth: 0,
  selectors: { '&:first-child': { borderTop: 'none', paddingTop: 0 } },
});
export const line = style({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'baseline',
  flexWrap: 'wrap',
  gap: 8,
  padding: '8px 0',
  borderTop: `1px solid ${vars.color.border}`,
  fontSize: 14,
  selectors: { '&:first-child': { borderTop: 'none' } },
});

export const row = style({
  display: 'flex',
  flexWrap: 'wrap',
  gap: 8,
  alignItems: 'flex-end',
});
export const column = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
});
export const three = style({
  display: 'grid',
  gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
  gap: 10,
});

const control = {
  minHeight: 40,
  padding: '0 14px',
  borderRadius: 10,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
} as const;
const disabled = {
  '&:disabled': { opacity: 0.45, cursor: 'default' },
} as const;
export const primary = style({
  ...control,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  fontWeight: 600,
  selectors: disabled,
});
export const secondary = style({
  ...control,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.text,
  selectors: {
    ...disabled,
    '&[aria-pressed="true"]': {
      background: vars.color.witness.surface,
      borderColor: vars.color.witness.border,
      color: vars.color.witness.text,
    },
  },
});
export const quiet = style({
  ...control,
  minHeight: 36,
  padding: '0 10px',
  border: 'none',
  background: 'none',
  color: vars.color.witness.accent,
  selectors: disabled,
});
export const link = style({
  color: vars.color.witness.accent,
  fontSize: 14,
  textDecoration: 'none',
});

export const field = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  minWidth: 0,
  fontSize: 12,
  color: vars.color.textMuted,
  // Side by side in a row, each takes a share; stacked in a column, its own height.
  selectors: { [`${row} > &`]: { flex: '1 1 200px' } },
});
const box = {
  width: '100%',
  borderRadius: 10,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.groundDeep,
  color: vars.color.text,
} as const;
export const input = style({
  ...box,
  minHeight: 40,
  padding: '0 12px',
  font: `14px ${font.ui}`,
});
export const textarea = style({
  ...box,
  padding: '10px 12px',
  font: `14px/20px ${font.ui}`,
  resize: 'vertical',
});
export const textareaMono = style({
  ...box,
  padding: '10px 12px',
  font: `13px/19px ${font.mono}`,
  resize: 'vertical',
});
export const check = style({
  display: 'flex',
  gap: 8,
  alignItems: 'center',
  fontSize: 14,
  color: vars.color.text,
});

export const token = style({
  display: 'block',
  padding: 10,
  borderRadius: 8,
  background: vars.color.groundDeep,
  font: `12px ${font.mono}`,
  overflowWrap: 'anywhere',
});

export const chip = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: 4,
  paddingLeft: 10,
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.borderStrong}`,
  font: `12px ${font.mono}`,
});
export const chips = style({
  display: 'flex',
  flexWrap: 'wrap',
  gap: 6,
  margin: 0,
  padding: 0,
  listStyle: 'none',
});

export const table = style({
  width: '100%',
  borderCollapse: 'collapse',
  fontSize: 14,
});
export const th = style({
  padding: '4px 0',
  textAlign: 'left',
  font: `500 11px ${font.mono}`,
  color: vars.color.textFaint,
});
export const td = style({
  padding: '8px 4px 8px 0',
  borderTop: `1px solid ${vars.color.border}`,
  verticalAlign: 'top',
});
export const num = style({ font: `13px ${font.mono}`, textAlign: 'right' });

export const answer = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  paddingTop: 12,
  borderTop: `1px solid ${vars.color.border}`,
});
export const failure = style({
  padding: '10px 12px',
  borderRadius: 10,
  background: status.warnSurface,
  border: `1px solid ${status.warnBorder}`,
  color: status.warnText,
  fontSize: 14,
});
export const refusal = style({
  padding: '10px 12px',
  borderRadius: 10,
  borderLeft: `3px solid ${vars.color.resident.border}`,
  background: vars.color.surface,
  fontFamily: font.voice,
  fontSize: 16,
  lineHeight: '24px',
  whiteSpace: 'pre-wrap',
});
export const trace = style({
  borderRadius: 8,
  background: vars.color.surface,
  padding: '8px 12px',
});
export const pre = style({
  margin: 0,
  font: `12px/18px ${font.mono}`,
  whiteSpace: 'pre-wrap',
  overflowWrap: 'anywhere',
  color: vars.color.textMuted,
});
export const marker = style({
  padding: '0 8px',
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.borderStrong}`,
  font: `11px/18px ${font.mono}`,
  selectors: {
    '&[data-mocked="true"]': {
      borderColor: status.warnBorder,
      background: status.warnSurface,
      color: status.warnText,
    },
  },
});
