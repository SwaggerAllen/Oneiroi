import { useState } from 'react';
import type { Ask, Pieces as PiecesData, Block, CorrespondenceMessage, HouseLetter, NeedsYouEntry, Reply } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Tabs } from '../../components/Tabs';
import { TopBar } from '../../components/TopBar';
import { Asks } from './Asks';
import { Pieces } from './Pieces';
import { isOpen, letterState, stateLine } from './letters';
import { Blocked, Correspondence, type GateActions, NeedsYou } from './NeedsYou';
import { Waiting } from './Waiting';
import { waitingEntries } from './queue';

export interface InboxProps {
  residentName: string;
  letters: HouseLetter[];
  messages?: CorrespondenceMessage[];
  replies?: Reply[];
  blocks?: Block[];
  actions?: GateActions;
  // The names a letter can go to, and how the witness sends one.
  addresses?: string[];
  onSendLetter?: (to: string, text: string) => void;
  asks?: Ask[];
  pieces?: PiecesData;
  onReviewPiece?: (path: string, decision: 'approve' | 'decline', note: string) => void;
  onAnswerAsk?: (number: number, decision: 'approve' | 'decline' | 'noted', note: string) => void;
  // What waits on you, from every system (brain#65).
  needsYou?: NeedsYouEntry[];
  // The instant ages are read against; now unless a story fixes it.
  now?: number;
}

type Tab = 'open' | 'all';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// Inbox (spec §10, screens/inbox.md): Waiting on you (everything that
// waits for his click, oldest first, only shown), Needs you (the replies waiting for
// your yes, the approved ones to send; xenia#13), the correspondence
// that reached the resident with a way to block a sender, the blocks
// (xenia#12), and the house letters between the resident's
// conversations (kumbukumbu#44).
export function Inbox({ residentName, letters, messages = [], replies = [], blocks = [], actions = {}, addresses = [], onSendLetter, asks = [], onAnswerAsk, pieces, onReviewPiece, needsYou = [], now }: InboxProps) {
  const [tab, setTab] = useState<Tab>('open');
  const newest = [...letters].sort((a, b) => b.number - a.number);
  const open = newest.filter((l) => isOpen(letterState(l, letters)));
  const shown = tab === 'open' ? open : newest;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Inbox" />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Waiting entries={waitingEntries(residentName, needsYou)} now={now} />
        {pieces ? (
          <div id="pieces" style={{ display: 'contents' }}>
            <Pieces residentName={residentName} pieces={pieces} onReview={onReviewPiece} />
          </div>
        ) : null}
        <div id="asks" style={{ display: 'contents' }}>
          <Asks residentName={residentName} asks={asks} onAnswer={onAnswerAsk} />
        </div>
        <NeedsYou
          residentName={residentName}
          drafted={replies.filter((r) => r.state === 'drafted')}
          approved={replies.filter((r) => r.state === 'approved')}
          actions={actions}
        />
        <Correspondence residentName={residentName} messages={messages} replies={replies} blocks={blocks} onBlock={actions.onBlock} />
        <Blocked residentName={residentName} blocks={blocks} onUnblock={actions.onUnblock} />
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
          {onSendLetter && addresses.length > 0 ? <WriteLetter residentName={residentName} addresses={addresses} onSend={onSendLetter} /> : null}
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

// A letter from you (kumbukumbu#44): to one of the resident's
// conversations by name, to Free time (a brief her next free time reads
// first), or to the house.
function WriteLetter({ residentName, addresses, onSend }: { residentName: string; addresses: string[]; onSend: (to: string, text: string) => void }) {
  const [to, setTo] = useState(addresses.includes('Free time') ? 'Free time' : addresses[0]);
  const [text, setText] = useState('');
  return (
    <details>
      <summary style={{ cursor: 'pointer', fontSize: 15, color: 'var(--witness)' }}>Write a letter</summary>
      <form
        aria-label="Write a letter"
        onSubmit={(e) => {
          e.preventDefault();
          if (text.trim()) {
            onSend(to, text.trim());
            setText('');
          }
        }}
        style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', marginTop: 'var(--space-2)' }}
      >
        <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
          <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>To</span>
          <select
            value={to}
            onChange={(e) => setTo(e.target.value)}
            style={{ minHeight: 'var(--control-h)', borderRadius: 'var(--radius-md)', border: '1px solid var(--hairline)', background: 'var(--surface-raised)', color: 'var(--ink)', fontSize: 15 }}
          >
            {addresses.map((a) => (
              <option key={a} value={a}>
                {a === 'house' ? `house (any of ${residentName}'s conversations)` : a === 'Free time' ? `Free time (${residentName}'s next free time)` : a}
              </option>
            ))}
          </select>
        </label>
        <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
          <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Letter</span>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={4}
            style={{ padding: 'var(--space-2) var(--space-3)', borderRadius: 'var(--radius-md)', border: '1px solid var(--hairline)', background: 'var(--surface-raised)', color: 'var(--ink)', fontFamily: 'var(--font-sans)', fontSize: 15 }}
          />
        </label>
        <div>
          <Button variant="primary" type="submit" disabled={text.trim() === ''}>
            Send the letter
          </Button>
        </div>
      </form>
    </details>
  );
}
