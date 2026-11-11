import { describe, expect, it } from 'vitest';
import { allZones, canAddSlot, isHours, isTime, isWindow, moveSlot } from './rules';

describe('rhythm rules', () => {
  it('reads times and windows', () => {
    expect(isTime('09:30')).toBe(true);
    expect(isTime('24:00')).toBe(false);
    expect(isTime('9:30')).toBe(false);
    expect(isWindow('08:00-22:00')).toBe(true);
    expect(isWindow('08:00')).toBe(false);
    expect(isWindow('08:00-22:00-23:00')).toBe(false);
    expect(isHours('4')).toBe(true);
    expect(isHours('0')).toBe(true);
    expect(isHours('four')).toBe(false);
  });

  it('moves a slot without ever dropping one', () => {
    expect(moveSlot(['10:00', '15:00'], '15:00', '16:30')).toEqual(['10:00', '16:30']);
    expect(moveSlot(['10:00'], '11:00', '12:00')).toEqual(['10:00']);
  });

  it('adds under the bound of four, never a duplicate', () => {
    expect(canAddSlot(['10:00'], '12:00')).toBe(true);
    expect(canAddSlot(['10:00'], '10:00')).toBe(false);
    expect(canAddSlot(['01:00', '02:00', '03:00', '04:00'], '05:00')).toBe(false);
    expect(canAddSlot([], '')).toBe(false);
  });

  it('offers the current zone and the device zone first among the known', () => {
    expect(allZones('Etc/UTC', 'America/Los_Angeles', ['Europe/Paris'])).toEqual(['America/Los_Angeles', 'Etc/UTC', 'Europe/Paris']);
    expect(allZones('Etc/UTC', null, ['Etc/UTC'])).toEqual(['Etc/UTC']);
  });
});
