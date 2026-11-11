import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { arrange, Journal, type JournalEntry } from './Journal';

const e = (number: number, kind: string, text: string, at: string): JournalEntry => ({ number, kind, register: null, text, at, by: 'resident', done_at: null });
const day = [
  e(1, 'note', 'the morning slot, palimpsest', '2026-11-11T09:35:00Z'),
  e(2, 'plan', 'his plan for Wednesday', '2026-11-11T07:31:00Z'),
  e(3, 'note', 'midnight slot', '2026-11-11T00:02:00Z'),
  e(4, 'wrap', 'the day closed', '2026-11-11T23:00:00Z'),
  e(5, 'note', 'a/very/long/path/without/a/space/anywhere/in/it/at/all', '2026-11-11T12:00:00Z'),
];

describe('journal arrange', () => {
  it('orders by kind, then by time either way', () => {
    expect(arrange(day, null, '', 'kind').map((x) => x.number)).toEqual([2, 1, 3, 5, 4]);
    expect(arrange(day, null, '', 'oldest').map((x) => x.number)).toEqual([3, 2, 1, 5, 4]);
    expect(arrange(day, null, '', 'newest').map((x) => x.number)).toEqual([4, 5, 1, 2, 3]);
  });

  it('filters by kind and searches the words, ignoring case', () => {
    expect(arrange(day, 'note', '', 'kind').map((x) => x.number)).toEqual([1, 3, 5]);
    expect(arrange(day, null, 'SLOT', 'oldest').map((x) => x.number)).toEqual([3, 1]);
    expect(arrange(day, 'plan', 'slot', 'kind')).toEqual([]);
  });
});

describe('Journal', () => {
  afterEach(cleanup);

  it('filters by kind from its chips and says how many of how many', () => {
    render(<Journal name="Wren" entries={day} />);
    expect(screen.getByText("WREN'S JOURNAL · 5")).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Note 3' }));
    expect(screen.getByText("WREN'S JOURNAL · 3 OF 5")).toBeTruthy();
    expect(screen.queryByText('his plan for Wednesday')).toBeNull();
    fireEvent.change(screen.getByRole('searchbox', { name: "Search the day's entries" }), { target: { value: 'nothing like this' } });
    expect(screen.getByText('No entry matches.')).toBeTruthy();
  });

  it('keeps the tools away from a short day', () => {
    render(<Journal name="Wren" entries={day.slice(0, 2)} />);
    expect(screen.queryByRole('searchbox')).toBeNull();
  });
});
