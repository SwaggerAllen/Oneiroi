import { useState } from 'react';
import type { HouseLetter } from '../../api/types';
import { Card } from '../../components/Card';
import { Tabs } from '../../components/Tabs';
import { TopBar } from '../../components/TopBar';
import { isOpen, letterState, stateLine } from './letters';

export interface InboxProps {
  residentName: string;
  letters: HouseLetter[];
}

type Tab = 'open' | 'all';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// Inbox (spec §10, screens/inbox.md). Built so far: Needs you, which has
// nothing to list until the correspondence gate exists, and the house
// letters, the work log between the resident's conversations
// (kumbukumbu #44), with where each stands read off the letters.
export function Inbox({ residentName, letters }: InboxProps) {
  const [tab, setTab] = useState<Tab>('open');
  const newest = [...letters].sort((a, b) => b.number - a.number);
  const open = newest.filter((l) => isOpen(letterState(l, letters)));
  const shown = tab === 'open' ? open : newest;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Inbox" />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Card title="Needs you">
          <p style={muted}>
            Nothing waits on you. Replies {residentName} drafts for you to send will show here once the sending gate is built.
          </p>
        </Card>
        <section aria-label="Letters" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          <h2 style={{ margin: 0, fontSize: 16, lineHeight: '22px', fontWeight: 600 }}>Letters between {residentName}’s conversations</h2>
          <Tabs<Tab>
            tabs={[
              { id: 'open', label: 'Open', count: open.length },
              { id: 'all', label: 'All', count: letters.length },
            ]}
            current={tab}
            onChange={setTab}
          />
          {shown.length === 0 ? (
            <p style={muted}>{letters.length === 0 ? 'No letters yet.' : 'Every letter has been answered.'}</p>
          ) : (
            <ol style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
              {shown.map((l) => (
                <Letter key={l.number} letter={l} all={letters} />
              ))}
            </ol>
          )}
        </section>
      </main>
    </div>
  );
}

function Letter({ letter, all }: { letter: HouseLetter; all: HouseLetter[] }) {
  const state = letterState(letter, all);
  const first = letter.text.split('\n').find((line) => line.trim() !== '') ?? '';
  return (
    <li>
      <Card>
        <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)' }}>
          #{letter.number} · {letter.from} → {letter.to} · {letter.sent_at.slice(0, 16).replace('T', ' ')} UTC
          {letter.in_reply_to ? ` · in reply to #${letter.in_reply_to}` : ''}
        </p>
        <p style={{ margin: 0, fontSize: 13, fontWeight: 500, color: isOpen(state) ? 'var(--witness)' : 'var(--ink-muted)' }}>{stateLine(state)}</p>
        <details>
          <summary style={{ cursor: 'pointer', fontSize: 15 }}>{first.length > 140 ? `${first.slice(0, 140)}…` : first}</summary>
          <p style={{ margin: 'var(--space-2) 0 0', fontSize: 15, whiteSpace: 'pre-wrap' }}>{letter.text}</p>
        </details>
        {letter.keepsake ? <p style={{ margin: 0, fontSize: 13 }}>With a keepsake: {letter.keepsake}</p> : null}
      </Card>
    </li>
  );
}
