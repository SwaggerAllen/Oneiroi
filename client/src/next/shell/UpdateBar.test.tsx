import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { useShell } from '../state/store';
import { UpdateBar } from './UpdateBar';

// apsu#35 (the witness, 2026-11-27): a page kept running the code from
// before a deploy until it was reloaded.
describe('the update bar', () => {
  beforeEach(() => useShell.setState({ build: null, newBuild: false }));
  afterEach(cleanup);

  it('keeps the first build named, and flags another one', () => {
    const { sawBuild } = useShell.getState();
    sawBuild(null);
    expect(useShell.getState().build).toBeNull();
    sawBuild('aaaa');
    sawBuild('aaaa');
    expect(useShell.getState()).toMatchObject({ build: 'aaaa', newBuild: false });
    sawBuild('bbbb');
    expect(useShell.getState()).toMatchObject({ build: 'aaaa', newBuild: true });
  });

  it('shows Reload only once the server names a newer build', () => {
    const { rerender } = render(<UpdateBar />);
    expect(screen.queryByText('Oneiroi has been updated')).toBeNull();
    useShell.getState().sawBuild('aaaa');
    useShell.getState().sawBuild('bbbb');
    rerender(<UpdateBar />);
    expect(screen.getByText('Oneiroi has been updated')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Reload' })).toBeTruthy();
  });
});
