// The month grid's arithmetic, pure: which days a month shows, Sunday
// first, with the previous and next months' edges blank.

export interface Cell {
  day: string | null; // YYYY-MM-DD, or null for a blank edge
  date: number | null;
}

export function monthCells(year: number, month: number): Cell[] {
  // month is 1-12; the Date API is 0-based and UTC keeps it zone-free.
  const first = new Date(Date.UTC(year, month - 1, 1));
  const days = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const lead = first.getUTCDay();
  const cells: Cell[] = Array.from({ length: lead }, () => ({ day: null, date: null }));
  for (let d = 1; d <= days; d++) {
    cells.push({ day: `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`, date: d });
  }
  while (cells.length % 7 !== 0) cells.push({ day: null, date: null });
  return cells;
}

export function shiftMonth(year: number, month: number, by: number): { year: number; month: number } {
  const index = year * 12 + (month - 1) + by;
  return { year: Math.floor(index / 12), month: (index % 12) + 1 };
}

export const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
