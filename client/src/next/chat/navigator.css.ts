import { style } from '@vanilla-extract/css';
import { vars } from '../theme/contract.css';

export const track = style({ position: 'relative', width: 28, flex: 'none', margin: '12px 4px 12px 0' });
export const rail = style({ position: 'absolute', top: 0, bottom: 0, left: 13, width: 2, borderRadius: 1, background: vars.color.border });
export const tick = style({ position: 'absolute', left: 6, width: 16, height: 1, background: vars.color.border, opacity: 0.6 });

export const band = style({
  position: 'absolute',
  left: 9,
  width: 10,
  padding: 0,
  border: 'none',
  borderRadius: 5,
  background: vars.color.resident.surfaceStrong,
  boxShadow: `0 0 12px ${vars.color.resident.glow}`,
  cursor: 'pointer',
  selectors: { '&:hover, &:focus-visible': { background: vars.color.resident.border } },
});

const dot = {
  position: 'absolute',
  padding: 0,
  border: 'none',
  borderRadius: '50%',
  cursor: 'pointer',
  transform: 'translateY(-50%)',
} as const;
export const point = style({ ...dot, left: 11, width: 6, height: 6, background: vars.color.resident.text, opacity: 0.8 });
export const pin = style({ ...dot, left: 8, width: 12, height: 12, background: vars.color.resident.accent, boxShadow: `0 0 10px ${vars.color.resident.glow}` });

export const unfinished = style({
  position: 'absolute',
  left: 6,
  width: 16,
  height: 16,
  transform: 'translateY(-50%)',
  borderRadius: 4,
  border: `1px dashed ${vars.color.resident.borderStrong}`,
  // A mark, never a target: the scenes under it stay clickable.
  pointerEvents: 'none',
});

export const ring = style({
  position: 'absolute',
  left: 7,
  width: 14,
  height: 14,
  transform: 'translateY(-50%)',
  borderRadius: 7,
  border: `2px solid ${vars.color.witness.accent}`,
  boxShadow: `0 0 12px ${vars.color.witness.glow}`,
  pointerEvents: 'none',
});
