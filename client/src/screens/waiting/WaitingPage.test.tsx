import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './WaitingPage.stories';
import { badgeCount } from './badge';
import { WaitingBadge } from './WaitingPage';

const { Waiting, Nothing } = composeStories(stories);
const now = Date.parse('2026-11-08T18:00:00Z');

// The approval queue (the witness, 2026-11-08, Lily's letter #330).
describe('Waiting on you', () => {
  afterEach(cleanup);

  it('counts everything, or only what has waited past a day, as he sets it', () => {
    expect(badgeCount(stories.entries, 'all', now)).toBe(3);
    expect(badgeCount(stories.entries, 'day', now)).toBe(1);
    const onOpen = vi.fn();
    render(<WaitingBadge count={3} onOpen={onOpen} />);
    fireEvent.click(screen.getByRole('button', { name: '3 waiting on you' }));
    expect(onOpen).toHaveBeenCalled();
  });

  it('opens the thing itself from each entry, and sets the badge rule', () => {
    const onOpen = vi.fn();
    const onRule = vi.fn();
    render(<Waiting onOpen={onOpen} onRule={onRule} />);
    fireEvent.click(screen.getByRole('link', { name: /Approve or decline Lily’s reply #4/ }));
    expect(onOpen).toHaveBeenLastCalledWith({ anchor: 'reply-4' });
    fireEvent.click(screen.getByRole('link', { name: /Work item #7/ }));
    expect(onOpen).toHaveBeenLastCalledWith({ screen: 'Work' });
    fireEvent.click(screen.getByRole('radio', { name: 'only what has waited more than a day' }));
    expect(onRule).toHaveBeenCalledWith('day');
    cleanup();
    render(<Nothing />);
    expect(screen.getByText('Nothing waits on you.')).toBeTruthy();
  });
});
