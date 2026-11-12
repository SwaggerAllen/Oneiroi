import { describe, expect, it } from 'vitest';
import { dayStart } from './dayStart';

describe('dayStart (kumbukumbu#67: her words by date)', () => {
  it('a day is the instant it starts in this zone, and `to` the next day’s start', () => {
    expect(dayStart('2026-11-12', 0)).toBe(new Date(2026, 10, 12).toISOString());
    expect(dayStart('2026-11-12', 1)).toBe(new Date(2026, 10, 13).toISOString());
    expect(dayStart('2026-12-31', 1)).toBe(new Date(2027, 0, 1).toISOString());
  });

  it('an empty or malformed day bounds nothing', () => {
    expect(dayStart('', 0)).toBeUndefined();
    expect(dayStart('12/11/2026', 0)).toBeUndefined();
  });
});
