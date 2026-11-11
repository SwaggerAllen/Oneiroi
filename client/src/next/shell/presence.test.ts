import { describe, expect, it } from 'vitest';
import { elapsed, presenceLine } from './presence';

describe('presence line', () => {
  it('times a running step', () => {
    expect(presenceLine({ state: 'tool', detail: 'document_write', since: 0 }, true, 14_000)).toBe(
      'document_write · 0:14',
    );
    expect(presenceLine({ state: 'thinking', since: 0 }, true, 3_000)).toBe('thinking · 0:03');
  });

  it('says only what it can know offline', () => {
    expect(presenceLine({ state: 'writing', since: 0 }, false, 1000)).toBe('offline · her turn may be running');
  });

  it('formats minutes', () => {
    expect(elapsed(125_000)).toBe('2:05');
  });
});
