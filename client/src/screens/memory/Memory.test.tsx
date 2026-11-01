import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it } from 'vitest';
import * as stories from './Memory.stories';

const { Empty, InTheIndex, IndexEmpty, WithTags } = composeStories(stories);

describe('Memory', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Empty, InTheIndex, IndexEmpty, WithTags]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it("opens on the index tab: the server's list and words, never a turn's marks", () => {
    render(<InTheIndex />);
    // The caption is the server's sentence, rendered as sent.
    expect(screen.getByText(/1 bookmark listed under a budget of 40 tokens \(a bound\)/)).toBeTruthy();
    // Listed by the server though no turn has marked it.
    expect(screen.getByText('in the index')).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'In the index 1' })).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'All 2' })).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'Pinned 1' })).toBeTruthy();
    expect(screen.getByRole('tab', { name: 'haven' })).toBeTruthy();
    expect(screen.queryByRole('tab', { name: 'care' })).toBeNull();
    expect(screen.getByText('the first time she said it back')).toBeTruthy();
    expect(screen.queryByText('the garden')).toBeNull();
  });

  it('an index listing nothing says why in the server words and shows no row', () => {
    render(<IndexEmpty />);
    expect(screen.getByRole('tab', { name: 'In the index 0' })).toBeTruthy();
    expect(screen.getByText(/listed only in that room's conversations/)).toBeTruthy();
    expect(screen.getByText('Nothing here.')).toBeTruthy();
  });

  it('a row once listed by a turn says when, beside whether the index holds it now', () => {
    render(<WithTags />);
    fireEvent.click(screen.getByRole('tab', { name: 'All 2' }));
    expect(screen.getByText('last listed in a turn 2026-10-20')).toBeTruthy();
    expect(screen.getAllByText('in the index')).toHaveLength(1);
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
