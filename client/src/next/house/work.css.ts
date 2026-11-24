import { style, styleVariants } from '@vanilla-extract/css';
import { font, radius, status, vars } from '../theme/contract.css';

// The house queue's pages (screen:next-house, the queue mocks of
// 2026-11-23): task cards, the layers drawn, the one document screen
// and its thread. In the house's tokens; nothing wider than the column.

export const top = style({ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap' });
export const pageTitle = style({ margin: 0, fontFamily: font.voice, fontWeight: 500, fontSize: 28, lineHeight: '34px', color: vars.color.text, overflowWrap: 'anywhere' });
export const section = style({ margin: '8px 0 0', font: `500 11px ${font.mono}`, letterSpacing: '0.06em', textTransform: 'uppercase', color: vars.color.textFaint });

export const segmented = style({ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' });
export const segment = style({
  minHeight: 34,
  padding: '0 12px',
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.borderStrong}`,
  background: 'none',
  color: vars.color.textMuted,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[aria-pressed="true"]': { background: vars.color.witness.surface, borderColor: vars.color.witness.border, color: vars.color.witness.text } },
});
export const select = style({
  minHeight: 34,
  padding: '0 10px',
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.groundDeep,
  color: vars.color.text,
  font: `13px ${font.ui}`,
  maxWidth: '100%',
});

/** A task's card: the whole card opens the task. */
export const card = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  padding: 14,
  borderRadius: radius.l,
  background: vars.color.surfaceRaised,
  border: `1px solid ${vars.color.border}`,
  minWidth: 0,
  textAlign: 'left',
  color: vars.color.text,
  font: `14px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&:hover': { borderColor: vars.color.borderStrong } },
});
export const cardMine = style([card, { borderColor: vars.color.witness.border }]);
export const cardHead = style({ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'baseline' });
export const cardTitle = style({ fontSize: 16, fontWeight: 600, lineHeight: '22px', overflowWrap: 'anywhere', minWidth: 0 });
export const number = style({ flex: 'none', font: `500 12px ${font.mono}`, color: vars.color.textFaint });
export const meta = style({ font: `500 11px ${font.mono}`, color: vars.color.textMuted, overflowWrap: 'anywhere' });
export const chips = style({ display: 'flex', flexWrap: 'wrap', gap: 6, minWidth: 0 });
export const docChip = style({
  display: 'inline-block',
  maxWidth: '100%',
  padding: '3px 9px',
  borderRadius: radius.s,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.groundDeep,
  color: vars.color.witness.accent,
  font: `12px ${font.mono}`,
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
  cursor: 'pointer',
});
export const nowRow = style({ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, fontSize: 14, minWidth: 0 });
// Where the step stands (2026-11-23): its own line under the name, quiet.
export const stepStatus = style({ flexBasis: '100%', paddingLeft: 16, fontSize: 12, color: vars.color.textMuted, overflowWrap: 'anywhere' });
export const dot = style({ width: 8, height: 8, borderRadius: '50%', flex: 'none' });
export const viewColor = styleVariants({
  ready: { background: vars.color.resident.accent },
  active: { background: vars.color.witness.accent },
  waiting: { background: vars.color.textFaint },
  blocked: { background: status.warn },
  failed: { background: status.error },
  done: { background: status.ok },
  skipped: { background: vars.color.textFaint },
});
export const typeWord = style({ font: `500 11px ${font.mono}`, color: vars.color.textFaint });
export const who = style({ padding: '1px 8px', borderRadius: radius.pill, font: `500 12px ${font.ui}`, background: vars.color.resident.surface, color: vars.color.resident.text, whiteSpace: 'nowrap' });
export const whoMe = style([who, { background: vars.color.witness.surface, color: vars.color.witness.text }]);
export const blocked = style({ fontSize: 13, lineHeight: '19px', color: status.warn, overflowWrap: 'anywhere' });

// ---- the layers drawn ----

export const layers = style({ display: 'flex', flexDirection: 'column', margin: 0, padding: 0, listStyle: 'none' });
export const layer = style({ display: 'grid', gridTemplateColumns: '28px 1fr', columnGap: 10, minWidth: 0 });
export const rail = style({ display: 'flex', flexDirection: 'column', alignItems: 'center' });
export const num = style({ width: 26, height: 26, borderRadius: '50%', display: 'grid', placeItems: 'center', font: `600 12px ${font.mono}`, flex: 'none' });
export const numState = styleVariants({
  done: { background: `color-mix(in srgb, ${status.ok} 16%, transparent)`, color: status.ok },
  open: { background: vars.color.witness.surface, color: vars.color.witness.text, boxShadow: `0 0 0 1px ${vars.color.witness.border}` },
  later: { background: vars.color.surface, color: vars.color.textFaint },
});
/** The connector down to the next layer, ending in its arrow. */
export const line = style({ flex: 1, width: 2, minHeight: 14, background: vars.color.border, position: 'relative', margin: '2px 0' });
export const arrow = style({ font: `11px ${font.mono}`, lineHeight: '10px', color: vars.color.textFaint, marginBottom: 2 });
export const layerBody = style({ display: 'flex', flexDirection: 'column', gap: 6, paddingBottom: 12, minWidth: 0 });
export const layerLabel = style({ font: `500 11px ${font.mono}`, color: vars.color.textFaint, minHeight: 26, display: 'flex', alignItems: 'center' });
export const layerLabelOpen = style([layerLabel, { color: vars.color.witness.text }]);
export const boxes = style({ display: 'flex', flexWrap: 'wrap', gap: 8, minWidth: 0 });
export const box = style({
  flex: '1 1 200px',
  maxWidth: '100%',
  minWidth: 0,
  display: 'flex',
  flexDirection: 'column',
  gap: 4,
  padding: '10px 12px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.border}`,
  background: vars.color.surfaceRaised,
  color: vars.color.text,
  textAlign: 'left',
  font: `14px ${font.ui}`,
  cursor: 'pointer',
  selectors: {
    '&[data-state="ready"]': { borderColor: vars.color.resident.border },
    '&[data-state="active"]': { borderColor: vars.color.witness.border, background: vars.color.witness.surface },
    '&[data-state="blocked"], &[data-state="failed"]': { borderColor: status.warnBorder },
    '&[data-state="done"], &[data-state="skipped"]': { opacity: 0.7 },
    '&:hover': { borderColor: vars.color.borderStrong },
  },
});
export const boxHead = style({ display: 'flex', justifyContent: 'space-between', gap: 6, font: `500 11px ${font.mono}`, color: vars.color.textFaint });
export const boxName = style({ fontWeight: 600, fontSize: 15, lineHeight: '20px', overflowWrap: 'anywhere' });
export const boxFoot = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 6, flexWrap: 'wrap' });
export const stateWord = styleVariants({
  ready: { font: `500 11px ${font.mono}`, color: vars.color.resident.text },
  active: { font: `500 11px ${font.mono}`, color: vars.color.witness.text },
  waiting: { font: `500 11px ${font.mono}`, color: vars.color.textFaint },
  blocked: { font: `500 11px ${font.mono}`, color: status.warn },
  failed: { font: `500 11px ${font.mono}`, color: status.error },
  done: { font: `500 11px ${font.mono}`, color: status.ok },
  skipped: { font: `500 11px ${font.mono}`, color: vars.color.textFaint },
});
export const gated = style({ padding: '0 6px', borderRadius: radius.pill, border: `1px solid ${status.warnBorder}`, color: status.warnText, font: `500 10px/16px ${font.mono}` });

// ---- documents ----

export const docs = style({ display: 'flex', flexDirection: 'column', margin: 0, padding: 0, listStyle: 'none' });
export const docRow = style({ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', borderTop: `1px solid ${vars.color.border}`, minWidth: 0, selectors: { '&:first-child': { borderTop: 'none' } } });
export const docMain = style({ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 });
export const docPath = style({ font: `12px ${font.mono}`, color: vars.color.textMuted, overflowWrap: 'anywhere' });
export const role = style({ flex: 'none', padding: '1px 8px', borderRadius: radius.pill, border: `1px solid ${vars.color.borderStrong}`, font: `500 11px ${font.mono}`, color: vars.color.textMuted });

// ---- the document screen ----

export const docScreen = style({ display: 'flex', flexDirection: 'column', gap: 12, minWidth: 0 });
export const citation = style({ font: `12px ${font.mono}`, color: vars.color.textMuted, overflowWrap: 'anywhere' });
export const taskLink = style({
  alignSelf: 'flex-start',
  maxWidth: '100%',
  padding: '6px 12px',
  borderRadius: radius.pill,
  border: `1px solid ${vars.color.witness.border}`,
  background: vars.color.witness.surface,
  color: vars.color.witness.text,
  font: `500 13px ${font.ui}`,
  cursor: 'pointer',
  overflowWrap: 'anywhere',
  textAlign: 'left',
});
export const body = style({ fontFamily: font.voice, fontSize: 18, lineHeight: '28px', color: vars.color.text, minWidth: 0, overflowWrap: 'anywhere' });

/** The floating bar at the document's foot: its thread, and a review open for you. */
export const floatBar = style({
  position: 'sticky',
  bottom: 0,
  zIndex: 2,
  display: 'flex',
  flexDirection: 'column',
  gap: 8,
  marginTop: 8,
  padding: 12,
  borderRadius: radius.l,
  border: `1px solid ${vars.color.borderStrong}`,
  background: vars.color.surfaceRaised,
  boxShadow: '0 -8px 24px -12px rgba(0,0,0,0.5)',
  minWidth: 0,
});
export const threadRow = style({
  display: 'flex',
  alignItems: 'center',
  gap: 8,
  minWidth: 0,
  padding: 0,
  border: 'none',
  background: 'none',
  color: vars.color.text,
  font: `14px ${font.ui}`,
  textAlign: 'left',
  cursor: 'pointer',
});
export const threadCount = style({ flex: 'none', font: `600 12px ${font.mono}`, color: vars.color.witness.accent });
export const threadLast = style({ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', color: vars.color.textMuted });
export const reviewLine = style({ fontSize: 13, lineHeight: '19px', color: vars.color.resident.text });

// ---- the thread sheet ----

export const scrim = style({ position: 'fixed', inset: 0, zIndex: 100, background: 'rgba(0,0,0,0.55)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' });
export const sheet = style({
  width: '100%',
  maxWidth: 640,
  maxHeight: '88vh',
  display: 'flex',
  flexDirection: 'column',
  borderRadius: `${radius.l} ${radius.l} 0 0`,
  background: vars.color.ground,
  border: `1px solid ${vars.color.borderStrong}`,
  borderBottom: 'none',
  minWidth: 0,
});
export const sheetHead = style({ display: 'flex', flexDirection: 'column', gap: 6, padding: '14px 16px 8px', borderBottom: `1px solid ${vars.color.border}` });
export const sheetTop = style({ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 });
export const sheetTitle = style({ margin: 0, font: `600 16px ${font.ui}`, overflowWrap: 'anywhere', minWidth: 0 });
export const messages = style({ flex: 1, minHeight: 120, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12, padding: '12px 16px' });
export const bubbleMine = style({ alignSelf: 'flex-end', maxWidth: '85%', padding: '8px 12px', borderRadius: '14px 14px 4px 14px', background: vars.color.witness.surface, color: vars.color.text, fontSize: 15, lineHeight: '21px', overflowWrap: 'anywhere', whiteSpace: 'pre-wrap' });
export const bubbleHers = style({ alignSelf: 'flex-start', maxWidth: '85%', padding: '8px 12px', borderRadius: '14px 14px 14px 4px', background: vars.color.resident.surface, color: vars.color.text, fontFamily: font.voice, fontSize: 16, lineHeight: '23px', overflowWrap: 'anywhere', whiteSpace: 'pre-wrap' });
export const byline = style({ font: `500 11px ${font.mono}`, color: vars.color.textFaint, marginTop: 4 });
export const platform = style({ alignSelf: 'stretch', padding: '8px 12px', borderRadius: radius.m, border: `1px dashed ${vars.color.borderStrong}`, font: `13px/19px ${font.ui}`, color: vars.color.textMuted, overflowWrap: 'anywhere', whiteSpace: 'pre-wrap' });
export const reply = style({ display: 'flex', gap: 8, alignItems: 'flex-end', padding: '10px 16px 16px', borderTop: `1px solid ${vars.color.border}` });
export const replyBox = style({ flex: 1, minWidth: 0, minHeight: 40, maxHeight: 160, padding: '9px 12px', borderRadius: 12, border: `1px solid ${vars.color.borderStrong}`, background: vars.color.groundDeep, color: vars.color.text, font: `14px/20px ${font.ui}`, resize: 'none' });

/** A picker over the page (Add to task). */
export const picker = style({ display: 'flex', flexDirection: 'column', gap: 8, padding: 12, borderRadius: radius.l, border: `1px solid ${vars.color.borderStrong}`, background: vars.color.surfaceRaised, minWidth: 0 });
export const pickRow = style({
  display: 'flex',
  flexDirection: 'column',
  gap: 2,
  padding: '8px 10px',
  borderRadius: radius.m,
  border: `1px solid ${vars.color.border}`,
  background: 'none',
  color: vars.color.text,
  textAlign: 'left',
  font: `14px ${font.ui}`,
  cursor: 'pointer',
  selectors: { '&[aria-pressed="true"]': { borderColor: vars.color.witness.border, background: vars.color.witness.surface } },
});
export const warnNote = style({ margin: 0, padding: '10px 12px', borderRadius: 10, background: status.warnSurface, border: `1px solid ${status.warnBorder}`, color: status.warnText, fontSize: 14, lineHeight: '20px' });
export const readOnly = style({ display: 'flex', flexDirection: 'column', gap: 2, padding: '8px 12px', borderRadius: 10, background: vars.color.groundDeep, fontSize: 15 });
