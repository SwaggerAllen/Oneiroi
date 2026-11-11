import { style } from '@vanilla-extract/css';
import { font, radius, vars } from '../theme/contract.css';

export const page = style({ display: 'flex', flexDirection: 'column', gap: 20, padding: '8px 16px 32px', maxWidth: 720, width: '100%', margin: '0 auto' });

export const agreement = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 10,
  padding: 16,
  borderRadius: radius.l,
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.witness.border}`,
  boxShadow: `0 0 36px -10px ${vars.color.witness.glow}`,
});

export const section = style({ display: 'flex', flexDirection: 'column', gap: 6 });
export const heading = style({ margin: '0 0 2px', font: `500 11px ${font.mono}`, letterSpacing: '0.04em', color: vars.color.textFaint });
export const headingWitness = style([heading, { color: vars.color.witness.accent }]);
export const meta = style({ margin: 0, font: `500 11px ${font.mono}`, color: vars.color.textMuted });
export const note = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });

export const terms = style({ display: 'flex', flexWrap: 'wrap', gap: 6 });
export const term = style({
  padding: '3px 8px',
  borderRadius: 6,
  background: vars.color.witness.surface,
  border: `1px solid ${vars.color.witness.border}`,
  color: vars.color.witness.text,
  font: `500 10px ${font.mono}`,
});

export const prose = style({ maxHeight: 420, overflowY: 'auto' });

export const decision = style({ display: 'flex', flexDirection: 'column', gap: 8 });
export const buttons = style({ display: 'flex', flexWrap: 'wrap', gap: 8 });

const buttonBase = { minHeight: 44, padding: '0 16px', borderRadius: radius.m, font: `500 14px ${font.ui}`, cursor: 'pointer' } as const;
export const primary = style({
  ...buttonBase,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  fontWeight: 600,
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});
export const secondary = style({
  ...buttonBase,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.text,
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});

const field = {
  width: '100%',
  padding: 12,
  borderRadius: radius.m,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  outline: 'none',
  resize: 'vertical',
} as const;
export const editor = style({ ...field, font: `14px/21px ${font.mono}` });
export const noteBox = style({ ...field, font: `14px/20px ${font.ui}` });

export const file = style({ borderRadius: 10, background: vars.color.surface, border: `1px solid ${vars.color.border}` });
export const fileHead = style({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  width: '100%',
  minHeight: 46,
  padding: '0 12px',
  border: 'none',
  background: 'none',
  color: vars.color.text,
  font: `500 13px ${font.mono}`,
  cursor: 'pointer',
});
export const fileBody = style({ padding: '0 14px 14px' });

export const pin = style({
  display: 'flex',
  gap: 10,
  padding: '10px 12px',
  borderRadius: 10,
  background: vars.color.resident.surface,
  border: `1px solid ${vars.color.resident.border}`,
  boxShadow: `0 8px 22px -16px ${vars.color.resident.glow}`,
  fontFamily: font.voice,
  fontSize: 16,
  lineHeight: '22px',
  color: vars.color.resident.text,
});
export const pinNumber = style({ font: `500 11px/22px ${font.mono}`, color: vars.color.textMuted, flex: 'none' });

export const vocabulary = style({ display: 'flex', flexWrap: 'wrap', gap: 6 });
export const word = style({ padding: '4px 10px', borderRadius: radius.pill, background: vars.color.surface, border: `1px solid ${vars.color.border}`, fontSize: 13 });

export const row = style({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  minHeight: 44,
  padding: '0 12px',
  borderRadius: 10,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  fontSize: 15,
});

// The stack's pages (character, consents, the agreement in full, an edit).
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
export const title = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 28 });
export const lead = style({ margin: 0, fontSize: 14, lineHeight: '21px', color: vars.color.textMuted });

// A row that opens a page.
export const link = style({
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  gap: 10,
  width: '100%',
  minHeight: 46,
  padding: '0 12px',
  borderRadius: 10,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.surface,
  color: vars.color.text,
  font: `15px ${font.ui}`,
  textAlign: 'left',
  cursor: 'pointer',
});
export const waits = style({ font: `500 11px ${font.mono}`, color: vars.color.witness.accent });

// A record card: hers (lilac) or plain.
const cardBase = { display: 'flex', flexDirection: 'column', gap: 6, padding: 12, borderRadius: 10 } as const;
export const card = style({ ...cardBase, background: vars.color.surface, border: `1px solid ${vars.color.border}` });
export const cardHers = style({ ...cardBase, background: vars.color.resident.surface, border: `1px solid ${vars.color.resident.border}` });
export const cardWaiting = style({ ...cardBase, background: vars.color.surfaceRaised, border: `1px solid ${vars.color.witness.border}` });
export const words = style({ margin: 0, fontFamily: font.voice, fontSize: 16, lineHeight: '22px', color: vars.color.resident.text, overflowWrap: 'anywhere' });
export const plain = style({ margin: 0, fontSize: 15, lineHeight: '21px', overflowWrap: 'anywhere' });
export const struck = style({ textDecoration: 'line-through', opacity: 0.65 });

export const input = style({ ...field, minHeight: 44, padding: '0 12px', font: `15px ${font.ui}` });
export const select = style({ ...field, minHeight: 44, padding: '0 10px', font: `15px ${font.ui}`, colorScheme: 'dark' });
export const formRow = style({ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'flex-end' });
export const label = style({ display: 'flex', flexDirection: 'column', gap: 4, flex: '1 1 160px', font: `500 11px ${font.mono}`, color: vars.color.textMuted });
export const check = style({ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 14, lineHeight: '20px' });
export const said = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.text });
export const small = style({
  minHeight: 36,
  padding: '0 12px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.witness.border}`,
  background: vars.color.witness.surface,
  color: vars.color.witness.accent,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.5, cursor: 'default' } },
});
export const pre = style({ margin: 0, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere', font: `13px/19px ${font.mono}`, color: vars.color.textMuted });
