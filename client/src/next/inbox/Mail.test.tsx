import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import type { HouseLetter } from '../../api/types';
import { MailThreadCard } from './Mail';
import * as css from './inbox.css';
import { mailThreads } from './mailThreads';

const letter = (n: number, reply: number | null, origin: HouseLetter['origin'], words: string): HouseLetter => ({
  number: n,
  from: 'x',
  to: 'Oneiroi chat',
  in_reply_to: reply,
  text: `letter ${n}`,
  keepsake: null,
  sent_at: '2026-11-19T10:00:00Z',
  read_by: [],
  read_at: null,
  origin,
  origin_words: words,
});

describe('a mail thread card', () => {
  // Vitest runs without globals, so testing-library's own cleanup never arms (conventions §9).
  afterEach(cleanup);

  // Report #22, and Work's read of #106: the resident's colour marks her
  // own letters, as it marks her replies in correspondence, never others'.
  it("marks her own letters in her colour and nobody else's", () => {
    const ls = [letter(1, null, 'housemate', 'your housemate Scarlett'), letter(2, 1, 'own', 'your own conversation “Oneiroi chat”')];
    render(<MailThreadCard thread={mailThreads(ls)[0]} all={ls} open />);
    const row = (n: number) => screen.getByText(`letter ${n}`, { selector: 'p' }).parentElement;
    expect(row(2)?.className).toContain(css.hers);
    expect(row(1)?.className ?? '').not.toContain(css.hers);
  });
});
