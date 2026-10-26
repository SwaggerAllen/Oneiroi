import type { StorybookConfig } from '@storybook/react-vite';

// Stories are the design agent's deliverable and the client's render
// tests (conventions §9): one story per state, state names as variation
// names. `build-storybook` is a gate, and Phoenix serves the built
// export on previews, which is what Design review reads (spec §11).
const config: StorybookConfig = {
  stories: ['../src/**/*.mdx', '../src/**/*.stories.@(ts|tsx)'],
  addons: ['@storybook/addon-a11y', '@storybook/addon-docs'],
  framework: '@storybook/react-vite',
};
export default config;
