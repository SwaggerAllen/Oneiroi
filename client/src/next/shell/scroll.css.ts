import { style } from '@vanilla-extract/css';

const FADE = '28px';

export const area = style({
  flex: 1,
  minHeight: 0,
  overflowY: 'auto',
  overscrollBehavior: 'contain',
  selectors: {
    '&[data-more-above="true"][data-more-below="false"]': {
      maskImage: `linear-gradient(to bottom, transparent 0, #000 ${FADE}, #000 100%)`,
    },
    '&[data-more-above="false"][data-more-below="true"]': {
      maskImage: `linear-gradient(to bottom, #000 0, #000 calc(100% - ${FADE}), transparent 100%)`,
    },
    '&[data-more-above="true"][data-more-below="true"]': {
      maskImage: `linear-gradient(to bottom, transparent 0, #000 ${FADE}, #000 calc(100% - ${FADE}), transparent 100%)`,
    },
  },
});

export const sentinel = style({ height: 1, flex: 'none' });
