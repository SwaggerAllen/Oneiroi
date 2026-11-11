import { style } from '@vanilla-extract/css';
import { font, radius, vars, wide } from '../theme/contract.css';

export const tab = style({ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' });
export const switcher = style({
  margin: '0 16px 4px',
  padding: 3,
  borderRadius: 12,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  display: 'flex',
  maxWidth: 480,
});
export const option = style({
  flex: 1,
  minHeight: 36,
  border: 'none',
  borderRadius: 9,
  background: 'none',
  color: vars.color.textMuted,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[data-selected]': { background: vars.color.surfaceRaised, color: vars.color.text } },
});
export const body = style({ flex: 1, minHeight: 0, display: 'flex' });
export const pane = style({ flex: 1, minHeight: 0, display: 'flex', selectors: { '&[hidden]': { display: 'none' } } });

export const page = style({ display: 'flex', flexDirection: 'column', gap: 14, padding: '10px 16px 28px', maxWidth: 720, width: '100%', margin: '0 auto' });

export const monthHead = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center' });
export const nav = style({ width: 44, height: 44, border: 'none', background: 'none', color: vars.color.textMuted, fontSize: 22, cursor: 'pointer' });
export const monthTitle = style({ display: 'flex', flexDirection: 'column', alignItems: 'center' });
export const monthName = style({ fontFamily: font.voice, fontSize: 24, fontWeight: 500 });
export const meta = style({ font: `500 11px ${font.mono}`, color: vars.color.textMuted });

export const weekdays = style({ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 4, font: `500 10px ${font.mono}`, color: vars.color.textFaint, textAlign: 'center' });
export const grid = style({ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 4 });
export const cell = style({
  height: 54,
  display: 'flex',
  flexDirection: 'column',
  justifyContent: 'space-between',
  padding: 6,
  borderRadius: 9,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.groundDeep,
  color: vars.color.textMuted,
  font: `500 12px ${font.ui}`,
  textAlign: 'left',
  cursor: 'pointer',
  '@media': { [wide]: { height: 72 } },
  selectors: {
    '&[data-past="true"]': { background: vars.color.surface, color: vars.color.text },
    '&[data-today="true"]': {
      background: vars.color.witness.surface,
      borderColor: vars.color.witness.accent,
      color: vars.color.witness.text,
      boxShadow: `0 0 16px -4px ${vars.color.witness.glow}`,
    },
  },
});
export const journalDot = style({ width: 6, height: 6, borderRadius: 3, background: vars.color.resident.accent });

export const note = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });

export const back = style({
  alignSelf: 'flex-start',
  minHeight: 40,
  padding: 0,
  border: 'none',
  background: 'none',
  color: vars.color.witness.accent,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
});
export const dayTitle = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 30 });
export const todayTag = style({ font: `500 11px ${font.mono}`, color: vars.color.witness.accent });

export const journal = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  padding: 14,
  borderRadius: 14,
  background: vars.color.resident.surface,
  border: `1px solid ${vars.color.resident.border}`,
  boxShadow: `0 10px 30px -18px ${vars.color.resident.glow}`,
});
export const entry = style({ display: 'grid', gridTemplateColumns: '52px 1fr', gap: 10 });
export const entryKind = style({ font: `500 11px/22px ${font.mono}`, color: vars.color.resident.text, opacity: 0.8 });
export const entryText = style({
  fontFamily: font.voice,
  fontSize: 16,
  lineHeight: '22px',
  color: vars.color.resident.text,
  selectors: { '&[data-done="true"]': { textDecoration: 'line-through', opacity: 0.7 } },
});

export const section = style({ display: 'flex', flexDirection: 'column', gap: 6 });
export const heading = style({ margin: '0 0 2px', font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });
export const headingHers = style([heading, { color: vars.color.resident.text }]);
export const headingWitness = style([heading, { color: vars.color.witness.accent }]);

const rowBase = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  minHeight: 46,
  padding: '0 12px',
  borderRadius: 10,
  fontSize: 15,
} as const;
export const row = style({ ...rowBase, background: vars.color.surface, border: `1px solid ${vars.color.border}` });
export const rowHers = style({ ...rowBase, background: vars.color.resident.surface, border: `1px solid ${vars.color.resident.border}` });

export const time = style({
  minHeight: 34,
  padding: '0 8px',
  borderRadius: 8,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  font: `500 13px ${font.mono}`,
  colorScheme: 'dark',
});
export const addRow = style({ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'center' });
export const addButton = style({
  minHeight: 38,
  padding: '0 14px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.witness.border}`,
  background: vars.color.witness.surface,
  color: vars.color.witness.accent,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});

// The month's marks under each date (sunna#48).
export const marks = style({ display: 'flex', alignItems: 'center', gap: 3, minHeight: 6 });
export const sessionDot = style({ width: 5, height: 5, borderRadius: 3, background: vars.color.witness.accent });
export const sceneBar = style({ height: 3, borderRadius: 2, background: vars.color.resident.border });
export const freeDot = style({ width: 6, height: 6, borderRadius: 3, border: `1px solid ${vars.color.resident.accent}` });

// Rhythm's editing (ported from the current client's Schedule).
export const card = style({ display: 'flex', flexDirection: 'column', gap: 8, padding: 12, borderRadius: 10, background: vars.color.surface, border: `1px solid ${vars.color.border}` });
export const cardHead = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10, fontSize: 15 });
export const form = style({ display: 'flex', flexDirection: 'column', gap: 8 });
export const text = style({
  width: '100%',
  padding: 10,
  borderRadius: radius.m,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  font: `14px/20px ${font.ui}`,
  resize: 'vertical',
});
export const fieldset = style({ display: 'flex', flexDirection: 'column', gap: 6, margin: 0, padding: 0, border: 0 });
export const check = style({ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 14, lineHeight: '20px' });
export const quiet = style({
  minHeight: 38,
  padding: '0 12px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.text,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});
