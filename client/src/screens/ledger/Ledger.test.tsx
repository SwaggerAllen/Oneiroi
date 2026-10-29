import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Ledger.stories';

const { NoKey, WithLines } = composeStories(stories);

describe('Ledger', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [NoKey, WithLines]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('says when no key is stored and that a line without a cap has no limit', () => {
    render(<NoKey />);
    expect(screen.getByText(/No key stored/)).toBeTruthy();
    expect(screen.getByText(/a purpose with no line has no limit/)).toBeTruthy();
  });

  it('shows a stopped line as stopped and sets a line through the form', () => {
    const onSetBudget = vi.fn();
    render(<WithLines onSetBudget={onSetBudget} />);
    expect(screen.getByText(/\$5\.02 of \$5\.00 a month, stopped/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Cap in dollars (blank for no limit)'), { target: { value: '12' } });
    fireEvent.click(screen.getByRole('button', { name: 'Set the line' }));
    expect(onSetBudget).toHaveBeenCalledWith('chat', '12', 'month');
  });
});
