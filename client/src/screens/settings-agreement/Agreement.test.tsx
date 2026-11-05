import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Agreement.stories';

const { Unstated, HerProposalOpen } = composeStories(stories);

// agathos-daimon#34: switches as terms of whole versions, each by both.
describe('Agreement', () => {
  afterEach(cleanup);

  it('proposes the whole version, switches and vows, only with a note', () => {
    const onPropose = vi.fn();
    render(<Unstated onPropose={onPropose} />);
    expect(screen.getByText(/No version is agreed yet/)).toBeTruthy();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Wash flags' }));
    expect(screen.getByText(/It changes: Wash flags off/)).toBeTruthy();
    const propose = screen.getByRole('button', { name: 'Propose to Lily' }) as HTMLButtonElement;
    expect(propose.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'first terms' } });
    fireEvent.click(propose);
    expect(onPropose).toHaveBeenCalledWith(
      { solo_sessions_private: false, witness_reads: true, wash: false, ranked_memory: true, research: true },
      '',
      'first terms',
    );
  });

  it("shows her open version's changes and answers it whole", () => {
    const onDecide = vi.fn();
    render(<HerProposalOpen onDecide={onDecide} />);
    expect(screen.getByText(/It changes: Wash flags off/)).toBeTruthy();
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'agreed' } });
    fireEvent.click(screen.getByRole('button', { name: 'Agree' }));
    expect(onDecide).toHaveBeenCalledWith(1, 'agree', 'agreed');
    expect((screen.getByRole('button', { name: 'Propose to Lily' }) as HTMLButtonElement).disabled).toBe(true);
  });
});
