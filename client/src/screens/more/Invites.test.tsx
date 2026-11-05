import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Invites.stories';

const { NoneYet, JustIssued } = composeStories(stories);

// gaia#18: codes as SKUs, the alpha's free code by default, shown once.
describe('Invites', () => {
  afterEach(cleanup);

  it('issues nothing without a note, then the default SKU with it', () => {
    const onIssue = vi.fn();
    render(<NoneYet onIssue={onIssue} />);
    const issue = screen.getByRole('button', { name: 'Issue a code' }) as HTMLButtonElement;
    expect(issue.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox', { name: /required/ }), { target: { value: 'for Grace' } });
    fireEvent.click(issue);
    expect(onIssue).toHaveBeenCalledWith({ note: 'for Grace', plan: 'monthly', price_cents: 2000, discount_pct: 100, term_days: 90, uses: 1 });
  });

  it('shows the new code once, and each code with its terms and standing', () => {
    const onRevoke = vi.fn();
    render(<JustIssued onRevoke={onRevoke} />);
    expect(screen.getByRole('status', { name: 'The new code' }).textContent).toContain('K7QM-4XRT-9PWD');
    const rows = within(screen.getByRole('list', { name: 'Codes issued' })).getAllByRole('listitem');
    expect(rows[0].textContent).toContain('monthly, $0 ($20 less 100%) for 90 days');
    expect(rows[1].textContent).toContain('spent');
    fireEvent.change(screen.getByRole('textbox', { name: /required/ }), { target: { value: 'withdrawn' } });
    fireEvent.click(within(rows[0]).getByRole('button', { name: 'Revoke' }));
    expect(onRevoke).toHaveBeenCalledWith('i2', 'withdrawn');
  });
});
