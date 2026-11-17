import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { CopyButton } from './CopyButton';

describe('a copy button says what happened (2026-11-17)', () => {
  afterEach(() => {
    cleanup();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('says Copied, then goes back to its label', async () => {
    vi.useFakeTimers();
    const write = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: write }, configurable: true });
    render(<CopyButton text="tok-1" label="Copy the token" />);
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Copy the token' }));
    });
    expect(write).toHaveBeenCalledWith('tok-1');
    expect(screen.getByRole('button', { name: 'Copied' })).toBeTruthy();
    act(() => {
      vi.advanceTimersByTime(2100);
    });
    expect(screen.getByRole('button', { name: 'Copy the token' })).toBeTruthy();
  });

  it('says so when the browser refuses, so it can be selected by hand', async () => {
    Object.defineProperty(navigator, 'clipboard', { value: { writeText: vi.fn().mockRejectedValue(new Error('no')) }, configurable: true });
    render(<CopyButton text="tok-1" />);
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Copy' }));
    });
    expect(screen.getByRole('button', { name: "Couldn't copy; select it" })).toBeTruthy();
  });
});
