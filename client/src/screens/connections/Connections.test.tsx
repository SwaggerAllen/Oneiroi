import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Connections.stories';

const { Connected, TokenIssued } = composeStories(stories);

describe('Connections', () => {
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Connected, TokenIssued]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('issues a reader token by name and role, and shows it once', () => {
    const onRegister = vi.fn();
    render(<Connected onRegister={onRegister} />);
    const form = screen.getByRole('form', { name: 'Connect something new' });
    const issue = within(form).getByRole('button', { name: 'Issue a token' }) as HTMLButtonElement;
    expect(issue.disabled).toBe(true);
    fireEvent.change(within(form).getByLabelText(/Name/), { target: { value: 'Scrape' } });
    fireEvent.click(issue);
    expect(onRegister).toHaveBeenCalledWith('scrape', 'reader');
    cleanup();
    render(<TokenIssued />);
    expect(screen.getByLabelText('Token').textContent).toContain('oneiroi_reader_');
    expect(screen.getByText(/shown this once/)).toBeTruthy();
  });

  it('revokes only once the button has become its consequence; revoked ones are listed apart', () => {
    const onRevoke = vi.fn();
    render(<Connected onRevoke={onRevoke} />);
    const live = screen.getByRole('list', { name: 'Connected' });
    fireEvent.click(within(live).getByRole('button', { name: 'Revoke' }));
    expect(onRevoke).not.toHaveBeenCalled();
    fireEvent.click(within(live).getByRole('button', { name: 'Revoke claude-code' }));
    expect(onRevoke).toHaveBeenCalledWith('claude-code');
    expect(screen.getByText(/laptop \(brain\) · revoked 2026-11-01/)).toBeTruthy();
  });
});
