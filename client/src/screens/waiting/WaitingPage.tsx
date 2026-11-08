import type { NeedsYouEntry } from '../../api/types';
import type { BadgeRule } from './badge';
import { Card } from '../../components/Card';
import { Waiting } from '../inbox/Waiting';
import { waitingEntries, type WaitingEntry } from '../inbox/queue';

// The badge, at the end of every screen's top bar: the count alone, and a way to
// the list. It decides nothing.
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
  rule: BadgeRule;
  onRule: (rule: BadgeRule) => void;
  // Into the thing itself: the draft, the ask, the screen it is decided on.
  onOpen: (where: WaitingEntry['where']) => void;
  now?: number;
}

// Waiting on you, its own page (the approval queue): everything whose
// next move is yours, oldest first, each opening the thing itself.
export function WaitingPage({ residentName, entries, rule, onRule, onOpen, now }: WaitingPageProps) {
  return (
    <>
      <Waiting entries={waitingEntries(residentName, entries)} now={now} onOpen={onOpen} />
      <Card title="The badge">
        <fieldset style={{ border: 0, margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          <legend style={{ fontSize: 15, marginBottom: 'var(--space-2)' }}>The count at the top right counts</legend>
          <label style={{ fontSize: 15, display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            <input type="radio" name="badge" checked={rule === 'all'} onChange={() => onRule('all')} />
            everything waiting on you
          </label>
          <label style={{ fontSize: 15, display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            <input type="radio" name="badge" checked={rule === 'day'} onChange={() => onRule('day')} />
            only what has waited more than a day
          </label>
        </fieldset>
        <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)' }}>Kept on this device. The list above always shows everything.</p>
      </Card>
    </>
  );
}
