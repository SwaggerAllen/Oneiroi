import { style } from '@vanilla-extract/css';
import { font, vars } from '../theme/contract.css';

/**
 * An open thread's header stays at the top of the list while its words
 * scroll under it (the witness, 2026-11-19: "mostly so I don't have to
 * scroll up to close the thread"). It sits inside the card, so it leaves
 * with the card; the negative margin covers the card's padding so the
 * words do not show around it.
 */
export const head = style({
  position: 'sticky',
  top: 0,
  zIndex: 1,
  margin: '-14px -14px 0',
  padding: '14px 14px 8px',
  borderRadius: '4px 16px 0 0',
  background: vars.color.surface,
  display: 'flex',
  alignItems: 'flex-start',
  gap: 12,
  selectors: { '&[data-open="true"]': { borderBottom: `1px solid ${vars.color.border}` } },
});

export const toggle = style({ all: 'unset', cursor: 'pointer', flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 4 });

export const close = style({
  all: 'unset',
  cursor: 'pointer',
  flexShrink: 0,
  font: `500 11px ${font.mono}`,
  color: vars.color.textFaint,
  padding: '2px 0',
  selectors: { '&:hover, &:focus-visible': { color: vars.color.text } },
});

/** The mentions line, above the list where it is always in view. */
export const bar = style({
  display: 'flex',
  flexWrap: 'wrap',
  justifyContent: 'center',
  alignItems: 'baseline',
  gap: 8,
  padding: '6px 16px',
  borderBottom: `1px solid ${vars.color.border}`,
  font: `500 11px ${font.mono}`,
  color: vars.color.textFaint,
});

/** Where the unread begins in an opened thread. */
export const fresh = style({
  display: 'flex',
  alignItems: 'center',
  gap: 10,
  font: `500 11px ${font.mono}`,
  color: vars.color.resident.text,
  selectors: { '&::before, &::after': { content: '""', flex: 1, borderTop: `1px solid ${vars.color.resident.border}` } },
});

/** A thread's unread count, on its card (the witness, 2026-11-20). */
export const badge = style({
  display: 'inline-block',
  padding: '1px 7px',
  borderRadius: 999,
  font: `600 11px ${font.mono}`,
  color: vars.color.resident.text,
  border: `1px solid ${vars.color.resident.border}`,
});

/** A reply he has not read, in its byline. */
export const pill = style({
  padding: '0 6px',
  borderRadius: 999,
  font: `600 10px ${font.mono}`,
  textTransform: 'uppercase',
  letterSpacing: '0.06em',
  color: vars.color.resident.text,
  border: `1px solid ${vars.color.resident.border}`,
});
