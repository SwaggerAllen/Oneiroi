import { render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { describe, expect, it } from 'vitest';
import * as stories from './Swatch.stories';
import tokens from '../tokens.json';

// Stories are the render tests: every story composes and renders in
// jsdom, with no browser and no network, which is what keeps `npm test`
// a CI gate rather than a cadence.
const { Default } = composeStories(stories);

describe('Swatch', () => {
  it('renders every colour token by name', () => {
    render(<Default />);
    for (const token of tokens.color.tokens) {
      expect(screen.getByText(token.name)).toBeTruthy();
    }
  });
});
