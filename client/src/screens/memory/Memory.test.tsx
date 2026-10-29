import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it } from 'vitest';
import * as stories from './Memory.stories';

const { Empty, InTheIndex, WithTags } = composeStories(stories);

describe('Memory', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, InTheIndex, WithTags]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('opens on the index tab with the budget as a caption and counts the tabs', () => {
    render(<InTheIndex />);
    expect(screen.getByText(/under 1500 tokens, a bound/)).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'In the index 1' })).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'All 2' })).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'Pinned 1' })).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'haven' })).toBeTruthy();
    expect(screen.queryByRole('tab', { name: 'care' })).toBeNull();
    expect(screen.getByText('the first time she said it back')).toBeTruthy();
    expect(screen.queryByText('the garden')).toBeNull();
  });

  it('a tag tab shows what carries it and search narrows the rows', () => {
    render(<WithTags />);
    fireEvent.click(screen.getByRole('tab', { name: 'All 2' }));
    expect(screen.getByText('the garden')).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Search bookmarks'), { target: { value: 'tomatoes' } });
    expect(screen.getByText('the garden')).toBeTruthy();
    expect(screen.queryByText('the first time she said it back')).toBeNull();
  });
});
