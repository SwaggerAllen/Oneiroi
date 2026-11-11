import { style } from '@vanilla-extract/css';
import { font, radius, vars, wide } from '../theme/contract.css';

// Onboarding is one reading column on every screen (the canvas's
// Onboarding row): a stranger reads it, then the same person writes in it.
export const page = style({ height: '100%', overflowY: 'auto', background: vars.color.ground, color: vars.color.text, fontFamily: font.ui });
export const column = style({
  maxWidth: 620,
  margin: '0 auto',
  padding: '20px 20px 48px',
  display: 'flex',
  flexDirection: 'column',
  gap: 18,
  '@media': { [wide]: { padding: '40px 24px 64px' } },
});
export const top = style({ display: 'flex', alignItems: 'center', justifyContent: 'space-between', minHeight: 44 });
export const brand = style({ fontFamily: font.voice, fontSize: 22, color: vars.color.text });
export const back = style({ minHeight: 44, padding: 0, border: 'none', background: 'none', color: vars.color.textMuted, font: `500 14px ${font.ui}`, cursor: 'pointer' });
export const eyebrow = style({ margin: 0, font: `500 11px ${font.mono}`, letterSpacing: '0.06em', textTransform: 'uppercase', color: vars.color.textFaint });
export const headline = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 36, lineHeight: '42px', textWrap: 'balance', '@media': { [wide]: { fontSize: 46, lineHeight: '52px' } } });
export const h1 = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 30, lineHeight: '36px', textWrap: 'balance' });
export const h2 = style({ margin: 0, font: `600 17px ${font.ui}` });
export const lede = style({ margin: 0, fontSize: 17, lineHeight: '27px', color: vars.color.text });
export const body = style({ margin: 0, fontSize: 15, lineHeight: '24px', color: vars.color.textMuted });
export const note = style({ margin: 0, fontSize: 13, lineHeight: '19px', color: vars.color.textMuted });
export const tag = style({ margin: 0, font: `500 10px ${font.mono}`, letterSpacing: '0.05em', textTransform: 'uppercase', color: vars.color.witness.accent });
export const said = style({ margin: 0, fontSize: 14, color: vars.color.witness.accent });

export const section = style({ display: 'flex', flexDirection: 'column', gap: 8, paddingTop: 18, borderTop: `1px solid ${vars.color.border}` });
export const voice = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 14,
  padding: 20,
  borderRadius: radius.l,
  background: vars.color.resident.surface,
  border: `1px solid ${vars.color.resident.border}`,
});
export const voiceText = style({ margin: 0, fontFamily: font.voice, fontSize: 18, lineHeight: '29px', color: vars.color.resident.text });
export const signoff = style({ margin: 0, fontFamily: font.voice, fontStyle: 'italic', fontSize: 15, color: vars.color.resident.text, opacity: 0.85 });
export const footer = style({ display: 'flex', flexWrap: 'wrap', gap: 16, paddingTop: 18, borderTop: `1px solid ${vars.color.border}`, fontSize: 13 });
export const link = style({ color: vars.color.textMuted, textDecoration: 'none', selectors: { '&:hover': { color: vars.color.text } } });

export const row = style({ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'center' });
const button = { minHeight: 48, padding: '0 18px', borderRadius: radius.m, font: `500 15px ${font.ui}`, cursor: 'pointer' } as const;
export const primary = style({
  ...button,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  fontWeight: 600,
  selectors: { '&:disabled': { opacity: 0.45, cursor: 'default' } },
});
export const secondary = style({
  ...button,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.text,
  selectors: { '&:disabled': { opacity: 0.45, cursor: 'default' } },
});
export const small = style({
  minHeight: 38,
  padding: '0 12px',
  borderRadius: 10,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.text,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.45, cursor: 'default' } },
});

export const card = style({ display: 'flex', flexDirection: 'column', gap: 10, padding: 16, borderRadius: radius.l, background: vars.color.surface, border: `1px solid ${vars.color.border}` });
export const choice = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  padding: 16,
  borderRadius: radius.l,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  color: vars.color.text,
  textAlign: 'left',
  font: `15px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[aria-pressed="true"]': { borderColor: vars.color.witness.accent, boxShadow: `0 0 0 1px ${vars.color.witness.accent}` } },
});
export const choices = style({ display: 'grid', gap: 10, gridTemplateColumns: '1fr', '@media': { [wide]: { gridTemplateColumns: '1fr 1fr' } } });
export const segment = style({ display: 'flex', padding: 3, gap: 3, borderRadius: 12, background: vars.color.surface, border: `1px solid ${vars.color.border}` });
export const segmentButton = style({
  flex: 1,
  minHeight: 40,
  borderRadius: 9,
  border: 'none',
  background: 'none',
  color: vars.color.textMuted,
  font: `500 14px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[aria-pressed="true"]': { background: vars.color.surfaceRaised, color: vars.color.text } },
});

export const field = style({ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 13, color: vars.color.textMuted });
const control = {
  minHeight: 46,
  padding: '0 14px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.groundDeep,
  color: vars.color.text,
  font: `16px ${font.ui}`,
} as const;
export const input = style(control);
export const textarea = style({ ...control, padding: 14, lineHeight: '24px', resize: 'vertical', minHeight: 220, fontFamily: font.mono, fontSize: 14 });
export const prompt = style({ ...control, padding: 14, lineHeight: '24px', resize: 'vertical', minHeight: 110 });

export const guidance = style({ margin: 0, fontSize: 15, lineHeight: '24px', color: vars.color.textMuted, whiteSpace: 'pre-wrap' });
export const drafted = style({ margin: 0, padding: '10px 12px', borderRadius: 10, background: vars.color.witness.surface, border: `1px solid ${vars.color.witness.border}`, fontSize: 13, lineHeight: '19px', color: vars.color.text });
export const progress = style({ height: 3, borderRadius: 2, background: vars.color.border, overflow: 'hidden' });
export const progressFill = style({ height: '100%', background: vars.color.witness.accent, transition: 'width 200ms ease' });

export const file = style({ display: 'flex', flexDirection: 'column', borderRadius: radius.l, border: `1px solid ${vars.color.border}`, background: vars.color.surface, overflow: 'hidden' });
export const fileHead = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 16px', font: `500 12px ${font.mono}` });
export const fileText = style({ margin: 0, padding: '0 16px 16px', maxHeight: 320, overflowY: 'auto', whiteSpace: 'pre-wrap', fontFamily: font.voice, fontSize: 16, lineHeight: '26px' });
export const check = style({ display: 'flex', gap: 10, alignItems: 'center', minHeight: 44, fontSize: 15 });

export const wake = style({ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22, paddingTop: 40, textAlign: 'center' });
export const wakeMark = style({
  width: 84,
  height: 84,
  borderRadius: 42,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontFamily: font.voice,
  fontSize: 36,
  background: vars.color.resident.surfaceStrong,
  color: vars.color.resident.text,
  boxShadow: `0 0 60px 10px ${vars.color.resident.glow}`,
});

// Get a read's notes (agathos-daimon#40): one a line, its kind first.
export const readNote = style({ display: 'flex', flexDirection: 'column', gap: 4, padding: '8px 0', borderTop: `1px solid ${vars.color.border}`, fontSize: 14, lineHeight: '21px' });
export const quote = style({ fontFamily: font.voice, fontStyle: 'italic', color: vars.color.resident.text });
