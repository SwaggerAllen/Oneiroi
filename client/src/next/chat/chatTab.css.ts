import { style } from '@vanilla-extract/css';
import { font, vars } from '../theme/contract.css';

export const tab = style({ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' });

export const switcher = style({
  margin: '0 16px 4px',
  padding: 3,
  borderRadius: 12,
  background: vars.color.surface,
  border: `1px solid ${vars.color.border}`,
  display: 'flex',
  alignSelf: 'stretch',
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
  selectors: {
    '&[data-selected]': { background: vars.color.surfaceRaised, color: vars.color.text, boxShadow: '0 2px 10px -2px rgba(0,0,0,0.6)' },
  },
});

export const body = style({ flex: 1, minHeight: 0, display: 'flex' });

export const pane = style({
  flex: 1,
  minHeight: 0,
  display: 'flex',
  selectors: { '&[hidden]': { display: 'none' } },
});
