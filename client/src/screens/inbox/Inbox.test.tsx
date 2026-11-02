import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it } from 'vitest';
import * as stories from './Inbox.stories';
import { letterState } from './letters';

const { Letters, NoLetters } = composeStories(stories);

describe('Inbox', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Letters, NoLetters]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('reads where each letter stands off the letters themselves', () => {
    const all = Letters.args.letters ?? [];
    const by = (n: number) => letterState(all.find((l) => l.number === n)!, all);
    expect(by(1)).toEqual({ kind: 'answered', by: 2 });
    expect(by(2)).toEqual({ kind: 'closed', readBy: ['Oneiroi chat'] });
    expect(by(3)).toEqual({ kind: 'waiting', on: 'the next free time', clock: true });
    expect(by(4)).toEqual({ kind: 'in_hand', readBy: ['Claude Code · Lily'] });
    expect(by(5)).toMatchObject({ kind: 'waiting', clock: false });
  });

  it('opens on the open letters, newest first, and shows all on the other tab', () => {
    render(<Letters />);
    const list = () => within(screen.getByRole('region', { name: 'Letters' })).getAllByRole('listitem');
    expect(list().map((li) => li.textContent?.match(/^#(\d+)/)?.[1])).toEqual(['5', '4', '3']);
    expect(screen.getByText('read by Claude Code · Lily, not answered yet')).toBeTruthy();
    expect(screen.getByText('waiting for the next free time')).toBeTruthy();
    expect(screen.getByText('With a keepsake: pocket-andrew.md')).toBeTruthy();
    fireEvent.click(screen.getByRole('tab', { name: 'All 5' }));
    expect(list()).toHaveLength(5);
    expect(screen.getByText('answered in #2')).toBeTruthy();
    expect(screen.getByText('read by Oneiroi chat')).toBeTruthy();
  });

  it('says honestly that nothing needs you yet, and when there are no letters', () => {
    render(<NoLetters />);
    expect(screen.getByText(/Nothing waits on you/)).toBeTruthy();
    expect(screen.getByText('No letters yet.')).toBeTruthy();
  });
});
