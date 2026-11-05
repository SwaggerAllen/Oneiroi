import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { Login } from './Login';

// gaia#19: sign-up behind the front door.
describe('Login', () => {
  afterEach(cleanup);

  it('offers no sign-up while the door is closed', () => {
    render(<Login onLogin={() => undefined} door="closed" />);
    expect(screen.queryByRole('button', { name: /invite|Create an account/ })).toBeNull();
  });

  it('behind an invite door, asks for a code and a long enough password before creating the account', () => {
    const onSignUp = vi.fn();
    render(<Login onLogin={() => undefined} door="invite" onSignUp={onSignUp} />);
    fireEvent.click(screen.getByRole('button', { name: 'I have an invite' }));
    const create = screen.getByRole('button', { name: 'Create account' }) as HTMLButtonElement;
    fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'grace@example.org' } });
    fireEvent.change(screen.getByLabelText(/Password/), { target: { value: 'long enough pw' } });
    expect(create.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Invite code'), { target: { value: ' k7qm-4xrt-9pwd ' } });
    fireEvent.click(create);
    expect(onSignUp).toHaveBeenCalledWith('grace@example.org', 'long enough pw', 'k7qm-4xrt-9pwd');
  });

  it('behind an open door, the code is optional', () => {
    const onSignUp = vi.fn();
    render(<Login onLogin={() => undefined} door="open" onSignUp={onSignUp} />);
    fireEvent.click(screen.getByRole('button', { name: 'Create an account' }));
    fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'x@example.org' } });
    fireEvent.change(screen.getByLabelText(/Password/), { target: { value: 'long enough pw' } });
    fireEvent.click(screen.getByRole('button', { name: 'Create account' }));
    expect(onSignUp).toHaveBeenCalledWith('x@example.org', 'long enough pw', null);
  });
});
