import type { NeedsYouEntry } from '../../api/types';
import { Waiting } from '../inbox/Waiting';
import { waitingEntries, type WaitingEntry } from '../inbox/queue';

// The badge, at the end of every screen's top bar: the count of
// everything waiting, from the moment it waits (the witness, 2026-11-08:
// "the badge should light up the moment that anything needs my attention
// or I'm not going to see it until 24 hours have passed"), and a way to
// the list. The count is the noise control; the list does the triage.
// It decides nothing.
export function WaitingBadge({ count, onOpen }: { count: number; onOpen: () => void }) {
  return (
    <button
      type="button"
      onClick={onOpen}
      aria-label={`${count} waiting on you`}
      style={{
        flex: 'none',
        marginLeft: 'var(--space-2)',
        minHeight: 32,
        padding: '0 var(--space-3)',
        borderRadius: 16,
        border: '1px solid var(--hairline)',
        background: count > 0 ? 'var(--witness)' : 'var(--surface)',
        color: count > 0 ? 'var(--on-witness, #fff)' : 'var(--ink-muted)',
        fontSize: 13,
        fontWeight: 600,
        cursor: 'pointer',
      }}
    >
      {count} waiting
    </button>
  );
}

export interface WaitingPageProps {
  residentName: string;
  entries: NeedsYouEntry[];
  // Into the thing itself: the draft, the ask, the screen it is decided on.
  onOpen: (where: WaitingEntry['where']) => void;
  now?: number;
}

// Waiting on you, its own page (the approval queue): everything whose
// next move is yours, oldest first, each opening the thing itself.
export function WaitingPage({ residentName, entries, onOpen, now }: WaitingPageProps) {
  return <Waiting entries={waitingEntries(residentName, entries)} now={now} onOpen={onOpen} />;
}
