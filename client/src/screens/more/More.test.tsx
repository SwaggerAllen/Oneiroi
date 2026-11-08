import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './More.stories';
import { BottomNav } from '../../components/BottomNav';

const { Built } = composeStories(stories);

describe('More', () => {
  afterEach(cleanup);

  it('opens the screens it holds, and the nav lights More while one is open', () => {
    const onOpen = vi.fn();
    render(<Built onOpen={onOpen} />);
    for (const name of ['Work', 'Library', 'Connections', 'Ledger', 'Regression']) fireEvent.click(screen.getByRole('button', { name }));
    expect(onOpen.mock.calls).toEqual([['work'], ['library'], ['connections'], ['ledger'], ['regression']]);
    cleanup();
    render(<BottomNav current="ledger" onChange={() => undefined} />);
    expect(screen.getByRole('button', { name: 'More' }).getAttribute('aria-current')).toBe('page');
    expect(screen.getAllByRole('button').map((b) => b.textContent)).toEqual(['Chat', 'Memory', 'Schedule', 'Inbox', 'More']);
  });
});
