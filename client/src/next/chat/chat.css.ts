import { globalStyle, style } from '@vanilla-extract/css';
import { font, status, vars, wide } from '../theme/contract.css';

export const column = style({
  flex: 1,
  minHeight: 0,
  // A flex item won't shrink below its content's width without this: one
  // wide code line or table would push the conversation off the screen.
  minWidth: 0,
  display: 'flex',
  flexDirection: 'column',
  width: '100%',
  maxWidth: 720,
  margin: '0 auto',
  position: 'relative',
});

export const list = style({ display: 'flex', flexDirection: 'column', gap: 16, padding: '12px 16px 16px' });

export const mine = style({
  alignSelf: 'flex-end',
  maxWidth: '82%',
  padding: '10px 14px',
  borderRadius: '16px 16px 4px 16px',
  background: vars.color.witness.surface,
  border: `1px solid ${vars.color.witness.border}`,
  color: vars.color.witness.text,
  fontSize: 15,
  lineHeight: '22px',
  whiteSpace: 'pre-wrap',
  overflowWrap: 'anywhere',
});

export const hers = style({
  minWidth: 0,
  overflowWrap: 'anywhere',
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  padding: 14,
  borderRadius: '4px 16px 16px 16px',
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  boxShadow: `0 10px 30px -18px ${vars.color.resident.glow}`,
  selectors: { '&[data-live="true"]': { borderColor: vars.color.resident.borderStrong } },
});

export const prose = style({ fontFamily: font.voice, fontSize: 18, lineHeight: '27px', color: vars.color.text, overflowWrap: 'anywhere' });
globalStyle(`${prose} p`, { margin: '0 0 10px' });
globalStyle(`${prose} p:last-child`, { marginBottom: 0 });
globalStyle(`${prose} h1, ${prose} h2, ${prose} h3`, { font: `600 14px ${font.ui}`, color: vars.color.resident.text, margin: '14px 0 6px' });
globalStyle(`${prose} code`, { font: `13px ${font.mono}`, background: vars.color.surfaceRaised, padding: '1px 5px', borderRadius: 4 });
globalStyle(`${prose} pre`, { background: vars.color.groundDeep, padding: 12, borderRadius: 8, overflowX: 'auto' });
globalStyle(`${prose} pre code`, { background: 'none', padding: 0 });
globalStyle(`${prose} blockquote`, { margin: 0, paddingLeft: 12, borderLeft: `2px solid ${vars.color.resident.border}`, fontStyle: 'italic', color: vars.color.textMuted });
globalStyle(`${prose} ul, ${prose} ol`, { paddingLeft: 22, margin: '0 0 10px' });
// A wide table scrolls inside the message rather than widening it.
globalStyle(`${prose} table`, { display: 'block', maxWidth: '100%', overflowX: 'auto', borderCollapse: 'collapse', font: `14px ${font.ui}` });
globalStyle(`${prose} th, ${prose} td`, { border: `1px solid ${vars.color.border}`, padding: '4px 8px' });

export const chip = style({
  display: 'inline-flex',
  alignItems: 'center',
  padding: '1px 7px',
  margin: '0 2px',
  borderRadius: 6,
  border: `1px solid ${vars.color.resident.border}`,
  background: vars.color.resident.surfaceStrong,
  color: vars.color.resident.text,
  font: `500 12px ${font.mono}`,
  verticalAlign: 'baseline',
  cursor: 'pointer',
});

export const meta = style({ display: 'flex', gap: 10, alignItems: 'center', font: `500 11px ${font.mono}`, color: vars.color.textFaint });

export const tool = style({
  alignSelf: 'flex-start',
  maxWidth: '100%',
  font: `500 11px ${font.mono}`,
  color: vars.color.textFaint,
  whiteSpace: 'nowrap',
  overflow: 'hidden',
  textOverflow: 'ellipsis',
});

// Centred, so its width is its content's: a long link must break here or it widens the conversation.
export const system = style({ alignSelf: 'center', maxWidth: '100%', overflowWrap: 'anywhere', font: `500 11px ${font.mono}`, color: vars.color.textFaint, textAlign: 'center' });

export const step = style({ display: 'flex', justifyContent: 'space-between', font: `500 11px ${font.mono}`, color: vars.color.resident.text });

export const caret = style({
  display: 'inline-block',
  width: 2,
  height: 18,
  marginLeft: 2,
  verticalAlign: -3,
  background: vars.color.resident.accent,
});

export const pendingLine = style({ alignSelf: 'flex-end', display: 'flex', gap: 8, alignItems: 'center', font: `500 10px ${font.mono}`, color: vars.color.textFaint, textTransform: 'uppercase' });

export const failed = style({ alignSelf: 'flex-end', display: 'flex', gap: 8, alignItems: 'center', fontSize: 12, color: status.error });

export const linkButton = style({
  background: 'none',
  border: 'none',
  padding: 0,
  color: vars.color.witness.accent,
  font: `500 12px ${font.ui}`,
  cursor: 'pointer',
});

export const unread = style({
  position: 'relative',
  height: 1,
  margin: '4px 0',
  background: `linear-gradient(to right, transparent, ${vars.color.witness.accent} 20%, ${vars.color.witness.accent} 80%, transparent)`,
  opacity: 0.7,
});

export const unreadLabel = style({
  position: 'absolute',
  left: '50%',
  top: -8,
  transform: 'translateX(-50%)',
  padding: '0 8px',
  background: vars.color.ground,
  font: `500 10px ${font.mono}`,
  color: vars.color.witness.accent,
});

export const older = style({ alignSelf: 'center', font: `500 11px ${font.mono}`, color: vars.color.textFaint, padding: 8 });

export const jump = style({
  position: 'absolute',
  right: 16,
  bottom: 84,
  minHeight: 36,
  padding: '0 12px',
  borderRadius: 18,
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.witness.border}`,
  color: vars.color.witness.accent,
  font: `500 12px ${font.ui}`,
  boxShadow: `0 8px 24px -6px rgba(0,0,0,0.8), 0 0 14px -4px ${vars.color.witness.glow}`,
  cursor: 'pointer',
  zIndex: 2,
});

export const composer = style({
  display: 'flex',
  alignItems: 'flex-end',
  gap: 8,
  padding: '8px 16px 10px',
  '@media': { [wide]: { paddingBottom: 16 } },
});

export const input = style({
  flex: 1,
  minHeight: 44,
  maxHeight: 180,
  overflowY: 'auto',
  resize: 'none',
  padding: '11px 14px',
  borderRadius: 22,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.surface,
  color: vars.color.text,
  font: `15px/22px ${font.ui}`,
  outline: 'none',
  selectors: { '&:focus': { borderColor: vars.color.witness.border } },
});

export const sendButton = style({
  width: 44,
  height: 44,
  flex: 'none',
  borderRadius: 22,
  border: 'none',
  background: vars.color.witness.accent,
  color: vars.color.witness.on,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  boxShadow: `0 0 16px -2px ${vars.color.witness.glow}`,
  cursor: 'pointer',
  selectors: { '&:disabled': { opacity: 0.4, cursor: 'default' } },
});

export const stopButton = style([
  sendButton,
  { background: vars.color.witness.surface, border: `1px solid ${vars.color.witness.accent}` },
]);

export const stopSquare = style({ width: 13, height: 13, borderRadius: 3, background: vars.color.witness.accent });

// A turn that failed with no message of his waiting on it (a check-in,
// free time), or one he can do something about (brain#88).
export const failedTurn = style({
  alignSelf: 'center',
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  maxWidth: 'min(560px, 100%)',
  minWidth: 0,
  padding: '10px 14px',
  borderRadius: 12,
  border: `1px solid ${status.error}`,
  font: `500 12px ${font.mono}`,
  color: status.error,
  overflowWrap: 'anywhere',
});
export const failedReason = style({ font: `13px ${font.ui}`, color: vars.color.text, lineHeight: '19px' });

// Domains (kumbukumbu#72): the bar above the composer naming the domain
// the next message goes in, its picker, and the rule where a stretch of
// the transcript changes domain.
export const domainBar = style({
  display: 'flex',
  flexWrap: 'wrap',
  alignItems: 'center',
  gap: 6,
  padding: '0 16px',
  font: `500 11px ${font.mono}`,
  color: vars.color.textFaint,
});

export const domainChip = style({
  display: 'inline-flex',
  alignItems: 'center',
  gap: 4,
  padding: '3px 10px',
  borderRadius: 999,
  border: `1px solid ${vars.color.border}`,
  background: 'transparent',
  color: vars.color.text,
  font: `500 11px ${font.mono}`,
  cursor: 'pointer',
  selectors: { '&[aria-expanded="true"]': { borderColor: vars.color.witness.accent } },
});

export const domainChipNamed = style({
  borderColor: vars.color.witness.accent,
  color: vars.color.witness.accent,
});

export const domainPicker = style({
  display: 'flex',
  flexWrap: 'wrap',
  alignItems: 'center',
  gap: 6,
  width: '100%',
  paddingTop: 6,
});

export const domainOption = style([
  domainChip,
  { selectors: { '&[aria-pressed="true"]': { borderColor: vars.color.witness.accent, color: vars.color.witness.accent } } },
]);

export const domainInput = style({
  minWidth: 0,
  width: 140,
  padding: '3px 10px',
  borderRadius: 999,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.ground,
  color: vars.color.text,
  font: `500 11px ${font.mono}`,
});

export const domainRule = style({
  alignSelf: 'center',
  display: 'flex',
  alignItems: 'center',
  gap: 8,
  font: `500 10px ${font.mono}`,
  letterSpacing: '0.06em',
  textTransform: 'uppercase',
  color: vars.color.textFaint,
});
