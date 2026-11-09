import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './GithubToken.stories';

const { None, Stored } = composeStories(stories);

// gaia#24: the witness sets, rotates and revokes the read token here.
describe('GitHub token', () => {
  afterEach(cleanup);

  it('stores a pasted token, and says reads are anonymous without one', () => {
    const onStore = vi.fn();
    render(<None onStore={onStore} />);
    expect(screen.getByText(/reads pull requests anonymously/)).toBeTruthy();
    fireEvent.change(screen.getByLabelText('Paste a token'), { target: { value: ' ghp_x ' } });
    fireEvent.click(screen.getByRole('button', { name: 'Store' }));
    expect(onStore).toHaveBeenCalledWith('ghp_x');
    expect(screen.queryByRole('button', { name: 'Revoke' })).toBeNull();
  });

  it('replaces or revokes a stored one, revoking only once the button has become its consequence', () => {
    const onRevoke = vi.fn();
    render(<Stored onRevoke={onRevoke} />);
    expect(screen.getByText(/stored since 2026-11-08/)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Revoke' }));
    expect(onRevoke).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Revoke the token' }));
    expect(onRevoke).toHaveBeenCalled();
  });
});
