import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './More.stories';
import { BottomNav } from '../../components/BottomNav';

const { Built } = composeStories(stories);

describe('More', () => {
  afterEach(cleanup);

  it('opens Ledger and Regression, and the nav lights More while either is open', () => {
    const onOpen = vi.fn();
    render(<Built onOpen={onOpen} />);
    fireEvent.click(screen.getByRole('button', { name: 'Ledger' }));
    fireEvent.click(screen.getByRole('button', { name: 'Regression' }));
    expect(onOpen.mock.calls).toEqual([['ledger'], ['regression']]);
    cleanup();
    render(<BottomNav current="ledger" onChange={() => undefined} />);
    expect(screen.getByRole('button', { name: 'More' }).getAttribute('aria-current')).toBe('page');
    expect(screen.getAllByRole('button').map((b) => b.textContent)).toEqual(['Chat', 'Memory', 'Schedule', 'Inbox', 'More']);
  });
});
