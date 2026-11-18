import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { useShell } from '../state/store';
import { BackBar, placeName } from './BackBar';

describe('back in Records (2026-11-17)', () => {
  afterEach(() => {
    cleanup();
    useShell.getState().resetStacks();
  });

  it('names a place as the reader would', () => {
    expect(placeName('')).toBe('Records');
    expect(placeName('doc/writing/the-bake-off.md')).toBe('the bake off');
    expect(placeName('dir/writing')).toBe('writing');
    expect(placeName('history/writing/the-bake-off.md')).toBe('History of the bake off');
  });

  it('steps back to the record it came from, or straight to Records', () => {
    useShell.setState((s) => ({ tab: 'records', stacks: { ...s.stacks, records: ['', 'doc/writing/weir.md', 'doc/scenes/2026-11-01.md'] } }));
    const back = vi.fn();
    render(<BackBar onBack={back} />);
    fireEvent.click(screen.getByRole('button', { name: '‹ weir' }));
    expect(back).toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Records' }));
    expect(useShell.getState().stacks.records).toEqual(['']);
  });

  it('one step from the root is only the one button', () => {
    useShell.setState((s) => ({ tab: 'records', stacks: { ...s.stacks, records: ['', 'doc/writing/weir.md'] } }));
    render(<BackBar onBack={() => undefined} />);
    expect(screen.getByRole('button', { name: '‹ Records' })).toBeTruthy();
    expect(screen.queryByRole('button', { name: 'Records' })).toBeNull();
  });
});
