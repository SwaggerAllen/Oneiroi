import { describe, expect, it } from 'vitest';
import { monthCells, shiftMonth } from './calendar';

describe('month grid', () => {
  it('starts November 2026 on a Sunday and ends it on the 30th', () => {
    const cells = monthCells(2026, 11);
    expect(cells[0]).toEqual({ day: '2026-11-01', date: 1 });
    expect(cells.filter((c) => c.day).length).toBe(30);
    expect(cells.length % 7).toBe(0);
  });

  it('pads the lead days of a month that starts mid-week', () => {
    // 1 October 2026 is a Thursday: four blanks first.
    expect(monthCells(2026, 10).slice(0, 5).map((c) => c.date)).toEqual([null, null, null, null, 1]);
  });

  it('shifts across a year', () => {
    expect(shiftMonth(2026, 12, 1)).toEqual({ year: 2027, month: 1 });
    expect(shiftMonth(2026, 1, -1)).toEqual({ year: 2025, month: 12 });
  });
});
