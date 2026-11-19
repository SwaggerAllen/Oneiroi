import type { HouseLetter } from '../../api/types';

/**
 * Letters grouped as threads (the witness, 2026-11-19: mail grouped as if
 * a shared-workspace thread, the same in the chat tab and the mail tab):
 * each thread is its first letter and every letter answering it, oldest
 * first; the threads newest first by their latest letter.
 */
export interface MailThread {
  root: number;
  letters: HouseLetter[];
  last: string;
}

export function rootOf(letter: HouseLetter, byNumber: Map<number, HouseLetter>): number {
  let l = letter;
  const seen = new Set<number>();
  while (l.in_reply_to !== null && byNumber.has(l.in_reply_to) && !seen.has(l.number)) {
    seen.add(l.number);
    l = byNumber.get(l.in_reply_to) as HouseLetter;
  }
  return l.number;
}

export function mailThreads(letters: HouseLetter[]): MailThread[] {
  const byNumber = new Map(letters.map((l) => [l.number, l]));
  const byRoot = new Map<number, HouseLetter[]>();
  for (const l of letters) {
    const root = rootOf(l, byNumber);
    byRoot.set(root, [...(byRoot.get(root) ?? []), l]);
  }
  return [...byRoot.entries()]
    .map(([root, ls]) => {
      const sorted = [...ls].sort((a, b) => a.number - b.number);
      return { root, letters: sorted, last: sorted[sorted.length - 1].sent_at };
    })
    .sort((a, b) => b.last.localeCompare(a.last));
}

/** Who a letter is from, plainly: hers, her witness's, a housemate's, the house's or the platform's (report #22). */
export function fromLine(l: HouseLetter): string {
  return l.origin_words ?? l.from;
}

/** The letter numbers a chat's letter wake names (its system note). */
export function wokeFor(content: string): number[] | null {
  if (!content.startsWith('You were woken in the Oneiroi chat because letters came for you here:')) return null;
  return [...content.matchAll(/#(\d+) from/g)].map((m) => Number(m[1]));
}
