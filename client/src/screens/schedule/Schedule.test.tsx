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
    pick('Slot 2', '14:30');
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
    pick('Time', '12:00');
    fireEvent.click(screen.getByRole('button', { name: 'Add the check-in' }));
    expect(onAddCheckin).toHaveBeenCalledWith('midday', '12:00');
    expect(screen.getByText(/Free time doesn't\./)).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Clear quiet hours' }));
    expect(onSetQuietHours).toHaveBeenCalledWith(null, null);
  });

  // The second check-in (the witness, 2026-11-03): the form clears its time
  // after an add, and on an iPhone a cleared time input looked set while it
  // was empty, so the button stayed disabled. The hour and minute are chosen,
  // and a chosen hour alone is a time on the hour.
  it('adds a second check-in after the first, the form cleared between them', () => {
    const onAddCheckin = vi.fn();
    render(<Today onAddCheckin={onAddCheckin} />);
    const add = screen.getByRole('button', { name: 'Add the check-in' }) as HTMLButtonElement;
    fireEvent.change(screen.getByLabelText('Label'), { target: { value: 'midday' } });
    pick('Time', '12:00');
    fireEvent.click(add);
    expect(add.disabled).toBe(true);
    expect((screen.getByLabelText('Time hour') as HTMLSelectElement).value).toBe('');
    fireEvent.change(screen.getByLabelText('Label'), { target: { value: 'evening' } });
    fireEvent.change(screen.getByLabelText('Time hour'), { target: { value: '21' } });
    expect(add.disabled).toBe(false);
    fireEvent.click(add);
    expect(onAddCheckin).toHaveBeenNthCalledWith(2, 'evening', '21:00');
  });

  it('says the zone every time is read in, and offers the device zone when they differ', () => {
    const onSetTimezone = vi.fn();
    render(<Today onSetTimezone={onSetTimezone} />);
    const device = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const zone = within(screen.getByRole('form', { name: 'Set the time zone' }));
    const set = zone.getByRole('button', { name: 'Set the zone' }) as HTMLButtonElement;
    expect(set.disabled).toBe(true);
    fireEvent.change(zone.getByLabelText('Zone'), { target: { value: 'Europe/London' } });
    fireEvent.click(set);
    expect(onSetTimezone).toHaveBeenCalledWith('Europe/London');
    if (device !== 'America/Los_Angeles') {
      fireEvent.click(zone.getByRole('button', { name: `Use ${device}` }));
      expect(onSetTimezone).toHaveBeenLastCalledWith(device);
    }
  });
});

// Picks a time by its hour and minute, as a person does.
function pick(label: string, time: string) {
  const [h, m] = time.split(':');
  fireEvent.change(screen.getByLabelText(`${label} hour`), { target: { value: h } });
  fireEvent.change(screen.getByLabelText(`${label} minute`), { target: { value: m } });
}
