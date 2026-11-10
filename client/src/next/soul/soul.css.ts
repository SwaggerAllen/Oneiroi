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
