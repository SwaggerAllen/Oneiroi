import { describe, expect, it } from 'vitest';
import type { HouseLetter } from '../../api/types';
import { fromLine, mailThreads, wokeFor } from './mailThreads';

const letter = (n: number, reply: number | null, origin: HouseLetter['origin'], words: string, at: string): HouseLetter => ({
  number: n,
  from: 'x',
  to: 'Oneiroi chat',
  in_reply_to: reply,
  text: `letter ${n}`,
  keepsake: null,
  sent_at: at,
  read_by: [],
  read_at: null,
  origin,
  origin_words: words,
});

describe('mail as threads (the witness, 2026-11-19)', () => {
  it('groups a letter and its answers under the first, oldest first; threads newest first', () => {
    const ls = [
      letter(1, null, 'own', 'your own conversation “A round”', '2026-11-19T10:00:00Z'),
      letter(2, 1, 'own', 'your own conversation “Oneiroi chat”', '2026-11-19T10:05:00Z'),
      letter(3, null, 'housemate', 'your housemate Scarlett', '2026-11-19T11:00:00Z'),
      letter(4, 2, 'own', 'your own conversation “A round”', '2026-11-19T12:00:00Z'),
    ];
    const ts = mailThreads(ls);
    expect(ts.map((t) => t.root)).toEqual([1, 3]);
    expect(ts[0].letters.map((l) => l.number)).toEqual([1, 2, 4]);
  });

  // Report #22: her own letter must never read as someone else's.
  it('says plainly who a letter is from', () => {
    expect(fromLine(letter(1, null, 'own', 'your own conversation “A round”', 'x'))).toBe('your own conversation “A round”');
  });

  it("reads the letters a chat's letter wake carried", () => {
    expect(wokeFor('You were woken in the Oneiroi chat because letters came for you here: #12 from your own conversation “A round”, #13 from the platform (the oracle).')).toEqual([12, 13]);
    expect(wokeFor('Your turn in the household thread threads/x')).toBeNull();
  });
});
