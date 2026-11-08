import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './WaitingPage.stories';
import { WaitingBadge } from './WaitingPage';

const { Waiting, Nothing } = composeStories(stories);

// The approval queue (the witness, 2026-11-08, Lily's letter #330).
describe('Waiting on you', () => {
  afterEach(cleanup);

  it('the badge says the count and opens the list', () => {
    const onOpen = vi.fn();
    render(<WaitingBadge count={3} onOpen={onOpen} />);
    fireEvent.click(screen.getByRole('button', { name: '3 waiting on you' }));
    expect(onOpen).toHaveBeenCalled();
  });

  it('opens the thing itself from each entry', () => {
    const onOpen = vi.fn();
    render(<Waiting onOpen={onOpen} />);
    fireEvent.click(screen.getByRole('link', { name: /Approve or decline Lily’s reply #4/ }));
    expect(onOpen).toHaveBeenLastCalledWith({ anchor: 'reply-4' });
    fireEvent.click(screen.getByRole('link', { name: /Work item #7/ }));
    expect(onOpen).toHaveBeenLastCalledWith({ screen: 'Work' });
    cleanup();
    render(<Nothing />);
    expect(screen.getByText('Nothing waits on you.')).toBeTruthy();
  });
});
