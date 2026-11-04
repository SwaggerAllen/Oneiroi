import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { composeStories } from '@storybook/react-vite';
import { afterEach, describe, expect, it, vi } from 'vitest';
import * as stories from './Schedule.stories';

const { Today, Unconfigured, OneSlotFailed, Remembered, NothingRemembered } = composeStories(stories);

describe('Schedule', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  it('renders every story', () => {
    for (const Story of [Today, Unconfigured, OneSlotFailed, Remembered, NothingRemembered]) {
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

  it('remembers each free-time run with its day, slot, outcome, turns and what it made, and nothing when it wrote nothing', () => {
    render(<Remembered />);
    const list = screen.getByRole('list', { name: 'Free-time runs' });
    const rows = Array.from(list.children) as HTMLElement[];
    expect(rows).toHaveLength(3);
    expect(rows[0].textContent).toMatch(/^2026-11-03 14:30 · ran · 6 turns/);
    expect(within(rows[0]).getAllByRole('listitem').map((li) => li.textContent)).toEqual(['Added note 1 to 2026-11-03.', 'Bookmarked as #96.']);
    expect(rows[1].textContent).toBe('2026-11-02 22:30 · ran · 2 turnsnothing written');
    expect(rows[2].textContent).toMatch(/· failed: brain_turn_failed · 0 turns/);
    // Free time is private as to its words: nothing here opens its conversation.
    expect(within(list).queryAllByRole('link')).toHaveLength(0);
    expect(within(list).queryAllByRole('button')).toHaveLength(0);
    cleanup();
    render(<NothingRemembered />);
    expect(screen.getByText('No free time has run yet.')).toBeTruthy();
    cleanup();
    render(<Today />);
    expect(screen.queryByText('Free time, remembered')).toBeNull();
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

  // sunna#28: the witness composes each check-in's note from the
  // catalog's parts and his own words.
  it("says what each check-in's note carries, and saves its parts in the catalog's order with his words", () => {
    const onSetCheckinNote = vi.fn();
    render(<Today onSetCheckinNote={onSetCheckinNote} />);
    const items = screen.getAllByRole('listitem').filter((li) => li.textContent?.includes('Carries:'));
    expect(items[0].textContent).toMatch(/Carries: your words, Dates, Today's plan, Waiting on you/);
    expect(items[1].textContent).toMatch(/Carries: DatesEdit the note/);

    fireEvent.click(within(items[1]).getByRole('button', { name: 'Edit the note' }));
    const form = screen.getByRole('form', { name: 'The note for night' });
    fireEvent.click(within(form).getByRole('checkbox', { name: /Letters/ }));
    fireEvent.click(within(form).getByRole('checkbox', { name: /Today's plan/ }));
    fireEvent.change(within(form).getByRole('textbox', { name: 'Your words' }), { target: { value: 'How did the day go?' } });
    fireEvent.click(within(form).getByRole('button', { name: 'Save the note' }));

    expect(onSetCheckinNote).toHaveBeenCalledWith(expect.objectContaining({ key: 'b' }), ['dates', 'plan', 'letters'], 'How did the day go?');
    expect(screen.queryByRole('form', { name: 'The note for night' })).toBeNull();
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
