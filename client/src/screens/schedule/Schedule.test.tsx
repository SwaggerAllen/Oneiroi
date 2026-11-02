import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Schedule.stories';

const { Today, Unconfigured, OneSlotFailed } = composeStories(stories);

describe('Schedule', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Today, Unconfigured, OneSlotFailed]) {
      const { unmount } = render(<Story />);
      unmount();
    }
  });

  it('shows each free-time slot with what it did today, and free time even when nothing is configured', () => {
    render(<Today />);
    const slots = within(screen.getByRole('list', { name: 'Free-time slots' })).getAllByRole('listitem');
    expect(slots.map((li) => li.textContent)).toEqual(['14:30 · ran today', '22:30 · not yet today']);
    cleanup();
    render(<Unconfigured />);
    expect(within(screen.getByRole('list', { name: 'Free-time slots' })).getAllByRole('listitem')).toHaveLength(2);
  });

  it('moves free time as the whole list, never to nothing, and never past four slots', () => {
    const onSetFreeTime = vi.fn();
    render(<OneSlotFailed onSetFreeTime={onSetFreeTime} />);
    const [slot] = within(screen.getByRole('list', { name: 'Free-time slots' })).getAllByRole('listitem');
    expect(slot.textContent).toBe('22:30 · today: failed: brain_turn_failed');
    // A list of one has no remove button: free time is never removed.
    expect(screen.queryByRole('button', { name: /Remove slot/ })).toBeNull();
    const save = screen.getByRole('button', { name: 'Save free time' }) as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    fireEvent.click(screen.getByRole('button', { name: 'Add a slot' }));
    fireEvent.change(screen.getByLabelText('Slot 2'), { target: { value: '14:30' } });
    fireEvent.click(save);
    expect(onSetFreeTime).toHaveBeenCalledWith(['22:30', '14:30']);
    fireEvent.click(screen.getByRole('button', { name: 'Add a slot' }));
    fireEvent.click(screen.getByRole('button', { name: 'Add a slot' }));
    expect(screen.queryByRole('button', { name: 'Add a slot' })).toBeNull();
    expect(screen.getByText(/At most 4 slots a day/)).toBeTruthy();
  });

  it('deletes a check-in only after the button has become its consequence', () => {
    const onDeleteCheckin = vi.fn();
    render(<Today onDeleteCheckin={onDeleteCheckin} />);
    fireEvent.click(screen.getAllByRole('button', { name: 'Delete' })[0]);
    expect(onDeleteCheckin).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Delete morning' }));
    expect(onDeleteCheckin).toHaveBeenCalledWith('a');
  });

  it('adds a check-in and sets or clears quiet hours', () => {
    const onAddCheckin = vi.fn();
    const onSetQuietHours = vi.fn();
    render(<Today onAddCheckin={onAddCheckin} onSetQuietHours={onSetQuietHours} />);
    fireEvent.change(screen.getByLabelText('Label'), { target: { value: 'midday' } });
    fireEvent.change(screen.getByLabelText('Time'), { target: { value: '12:00' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add the check-in' }));
    expect(onAddCheckin).toHaveBeenCalledWith('midday', '12:00');
    expect(screen.getByText(/Free time doesn't\./)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Clear quiet hours' }));
    expect(onSetQuietHours).toHaveBeenCalledWith(null, null);
  });
});
