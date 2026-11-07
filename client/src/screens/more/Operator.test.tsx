import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Operator.stories';
import { Operator } from './Operator';

const { Closed, InviteWithAnAdmin } = composeStories(stories);

// gaia#16: the front door and the roles, every change with a note.
describe('Operator', () => {
  afterEach(cleanup);

  it('changes nothing without a note, then opens the door to invites with it', () => {
    const onSetGate = vi.fn();
    render(<Closed onSetGate={onSetGate} />);
    const invite = within(screen.getByRole('group', { name: 'The front door' })).getByRole('button', { name: 'Invite' }) as HTMLButtonElement;
    expect(invite.disabled).toBe(true);
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'the alpha' } });
    fireEvent.click(invite);
    expect(onSetGate).toHaveBeenCalledWith('invite', 'the alpha');
  });

  it('lists the roles and grants and revokes them, each with the note', () => {
    const onGrant = vi.fn();
    const onRevoke = vi.fn();
    render(<InviteWithAnAdmin onGrant={onGrant} onRevoke={onRevoke} />);
    expect(within(screen.getByRole('list', { name: 'Platform roles' })).getAllByRole('listitem')).toHaveLength(2);
    fireEvent.change(screen.getByRole('textbox', { name: /note/ }), { target: { value: 'hand-off' } });
    fireEvent.change(screen.getByRole('textbox', { name: 'Account email' }), { target: { value: 'next@example.com' } });
    fireEvent.click(screen.getByRole('button', { name: 'Grant' }));
    expect(onGrant).toHaveBeenCalledWith('next@example.com', 'admin', 'hand-off');
    fireEvent.click(screen.getAllByRole('button', { name: 'Revoke' })[1]);
    expect(onRevoke).toHaveBeenCalledWith('a2', 'admin', 'hand-off');
  });

  it('lists the latest restarts as their lines', () => {
    const platform = {
      gate: { state: 'invite' as const, note: null, set_by: null, set_at: null },
      roles: [],
      restarts: [{ number: 2, commit: 'f7628c2aa', previous: '321ade4bb', changed: true, booted_at: '2026-11-07T00:05:00Z', line: 'The platform restarted at 2026-11-07 00:05 UTC: commit 321ade4 → f7628c2, changed.' }],
    };
    render(<Operator platform={platform} />);
    expect(screen.getByText(/#2 The platform restarted at 2026-11-07 00:05 UTC/)).toBeTruthy();
  });
});
