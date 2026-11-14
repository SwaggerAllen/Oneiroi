import { describe, expect, it } from 'vitest';
import { bars, count, ms, unitName } from './hour';

describe('the public hour (apsu#29)', () => {
  it('says times as a reader takes them', () => {
    expect(ms(null)).toBe('—');
    expect(ms(40)).toBe('40 ms');
    expect(ms(1_200)).toBe('1.2 s');
    expect(ms(25_000)).toBe('25 s');
    expect(ms(60_000)).toBe('60 s+');
  });

  it('keeps "few" as few, and names a job by its last part', () => {
    expect(count('few')).toBe('few');
    expect(count(12)).toBe('12');
    expect(unitName('job', 'Oneiroi.Sunna.WorkWorker')).toBe('WorkWorker');
    expect(unitName('http', 'GET /v1/residents/:id/needs_you')).toBe('GET /v1/residents/:id/needs_you');
  });

  it('draws the trend against its busiest bucket, "few" as a sliver', () => {
    expect(bars([{ units: 10 }, { units: 'few' }, { units: 0 }, { units: 20 }])).toEqual([0.5, 0.1, 0, 1]);
  });
});
