import type { Preview } from '@storybook/react-vite';
import '../src/theme.css';

// Both themes are first-class (the design system's README): every story
// renders under each, selected here rather than per story.
const preview: Preview = {
  globalTypes: {
    theme: {
      description: 'Colour theme',
      toolbar: { icon: 'mirror', items: ['light', 'dark'], dynamicTitle: true },
    },
  },
  initialGlobals: { theme: 'light' },
  decorators: [
    (Story, context) => {
      document.documentElement.dataset.theme = String(context.globals.theme ?? 'light');
      return <Story />;
    },
  ],
};
export default preview;
