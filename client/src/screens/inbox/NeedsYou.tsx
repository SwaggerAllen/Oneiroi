import { useState } from 'react';
import type { Block, CorrespondenceMessage, Reply } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface GateActions {
  onDecideReply?: (number: number, approve: boolean, note: string) => void;
  onMarkSent?: (number: number, url: string | null) => void;
  onBlock?: (m: CorrespondenceMessage, note: string) => void;
  onUnblock?: (b: Block, note: string) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const meta = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;
const item = {
  display: 'flex',
  flexDirection: 'column',
  gap: 'var(--space-2)',
  borderTop: '1px solid var(--hairline)',
  paddingTop: 'var(--space-3)',
} as const;
const when = (at: string) => `${at.slice(0, 16).replace('T', ' ')} UTC`;

function firstLine(text: string): string {
  const line = text.split('\n').find((l) => l.trim() !== '') ?? '';
  return line.length > 140 ? `${line.slice(0, 140)}…` : line;
}

// Needs you (spec §10, xenia #13): the replies the resident drafted that
// wait for your yes, and the approved ones not yet sent. Every decision
// carries a note, which the resident reads first.
export function NeedsYou({
  residentName,
  drafted,
  approved,
  actions,
}: {
  residentName: string;
  drafted: Reply[];
  approved: Reply[];
  actions: GateActions;
}) {
  return (
    <Card title="Needs you">
      {drafted.length + approved.length === 0 ? (
        <p style={muted}>Nothing waits on you.</p>
      ) : (
        <ol aria-label="Needs you" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          {drafted.map((r) => (
            <DraftedReply key={`r${r.number}`} residentName={residentName} reply={r} onDecide={actions.onDecideReply} />
          ))}
          {approved.map((r) => (
            <ApprovedReply key={`s${r.number}`} reply={r} onMarkSent={actions.onMarkSent} />
          ))}
        </ol>
      )}
    </Card>
  );
}

function DraftedReply({ residentName, reply: r, onDecide }: { residentName: string; reply: Reply; onDecide?: GateActions['onDecideReply'] }) {
  const [note, setNote] = useState('');
  return (
    <li style={item}>
      <p style={meta}>
        {residentName}’s reply #{r.number} · to {r.to} on {r.platform}
        {r.in_reply_to ? ` · answering message #${r.in_reply_to}` : ''}
      </p>
      <p style={{ margin: 0, fontSize: 15, whiteSpace: 'pre-wrap' }}>{r.text}</p>
      {onDecide ? (
        <form aria-label={`Decide reply ${r.number}`} onSubmit={(e) => e.preventDefault()} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          <Field label={`Your note to ${residentName}`} value={note} onChange={(e) => setNote(e.target.value)} />
          <div style={row}>
            <Button variant="primary" type="button" disabled={note.trim() === ''} onClick={() => onDecide(r.number, true, note.trim())}>
              Approve to send
            </Button>
            <Button type="button" disabled={note.trim() === ''} onClick={() => onDecide(r.number, false, note.trim())}>
              Decline
            </Button>
          </div>
        </form>
      ) : null}
    </li>
  );
}

function ApprovedReply({ reply: r, onMarkSent }: { reply: Reply; onMarkSent?: GateActions['onMarkSent'] }) {
  const [url, setUrl] = useState('');
  return (
    <li style={item}>
      <p style={meta}>
        Reply #{r.number} · to {r.to} on {r.platform} · approved, waiting to be sent
      </p>
      <p style={{ margin: 0, fontSize: 15, whiteSpace: 'pre-wrap' }}>{r.text}</p>
      {onMarkSent ? (
        <form
          aria-label={`Mark reply ${r.number} sent`}
          onSubmit={(e) => {
            e.preventDefault();
            onMarkSent(r.number, url.trim() === '' ? null : url.trim());
          }}
          style={row}
        >
          <Field label="Where it is now (optional)" value={url} onChange={(e) => setUrl(e.target.value)} />
          <Button type="submit">I sent it</Button>
        </form>
      ) : null}
    </li>
  );
}

// Correspondence (xenia #12): every message that reached the resident,
// newest first; a blocked sender's is a line with no words. Blocking a
// sender asks why, in place.
export function Correspondence({
  residentName,
  messages,
  blocks,
  onBlock,
}: {
  residentName: string;
  messages: CorrespondenceMessage[];
  blocks: Block[];
  onBlock?: GateActions['onBlock'];
}) {
  const blocked = new Set(blocks.map((b) => `${b.platform}:${b.identity}`));
  return (
    <Card title="Correspondence">
      <p style={muted}>Messages to {residentName} from outside the house, which reach {residentName} as they arrive.</p>
      {messages.length === 0 ? (
        <p style={muted}>None yet.</p>
      ) : (
        <ol aria-label="Correspondence" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          {messages.map((m) => (
            <Message key={m.number} message={m} blocked={blocked.has(`${m.platform}:${m.sender}`)} onBlock={onBlock} />
          ))}
        </ol>
      )}
    </Card>
  );
}

function Message({ message: m, blocked, onBlock }: { message: CorrespondenceMessage; blocked: boolean; onBlock?: GateActions['onBlock'] }) {
  const [blocking, setBlocking] = useState(false);
  const [note, setNote] = useState('');
  const from = m.sender_name ? `${m.sender_name} <${m.sender}>` : m.sender;
  if (m.state === 'blocked')
    return (
      <li style={item}>
        <p style={meta}>
          Message #{m.number} · {m.platform} · from {m.sender} · {when(m.sent_at)} · blocked, not kept
        </p>
      </li>
    );
  return (
    <li style={item}>
      <p style={meta}>
        Message #{m.number} · {m.platform} · from {from} · {when(m.sent_at)} · {m.read_at ? 'read' : 'unread'}
        {m.verified ? '' : ' · sender not verified'}
      </p>
      {m.subject ? <p style={{ margin: 0, fontSize: 15, fontWeight: 600 }}>{m.subject}</p> : null}
      <details>
        <summary style={{ cursor: 'pointer', fontSize: 15 }}>{firstLine(m.text ?? '')}</summary>
        <p style={{ margin: 'var(--space-2) 0 0', fontSize: 15, whiteSpace: 'pre-wrap' }}>{m.text}</p>
      </details>
      {onBlock && !blocked ? (
        blocking ? (
          <div style={row}>
            <Field label="Why" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button type="button" disabled={note.trim() === ''} onClick={() => onBlock(m, note.trim())}>
              Block {m.sender}
            </Button>
          </div>
        ) : (
          <div>
            <Button type="button" variant="quiet" onClick={() => setBlocking(true)}>
              Block sender
            </Button>
          </div>
        )
      ) : null}
    </li>
  );
}

// The blocks (xenia #12): whose messages are counted and never kept, and
// who set each. A block is lifted only by whoever set it, so one the
// resident set has no button here.
export function Blocked({ residentName, blocks, onUnblock }: { residentName: string; blocks: Block[]; onUnblock?: GateActions['onUnblock'] }) {
  return (
    <Card title="Blocked">
      <p style={muted}>Their messages are counted and never kept. Each block is lifted only by whoever set it.</p>
      {blocks.length === 0 ? (
        <p style={muted}>Nobody.</p>
      ) : (
        <ul aria-label="Blocked" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          {blocks.map((b) => (
            <BlockRow key={`${b.platform}:${b.identity}`} residentName={residentName} block={b} onUnblock={onUnblock} />
          ))}
        </ul>
      )}
    </Card>
  );
}

function BlockRow({ residentName, block: b, onUnblock }: { residentName: string; block: Block; onUnblock?: GateActions['onUnblock'] }) {
  const [lifting, setLifting] = useState(false);
  const [note, setNote] = useState('');
  const mine = b.blocked_by === 'witness';
  return (
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', fontSize: 15 }}>
      <span>
        {b.name ? `${b.name} · ` : ''}
        {b.identity} <span style={{ color: 'var(--ink-muted)' }}>on {b.platform} · {mine ? 'by you' : `by ${residentName}`}: {b.note}</span>
      </span>
      {onUnblock && mine ? (
        lifting ? (
          <div style={row}>
            <Field label="Why lift it" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button type="button" disabled={note.trim() === ''} onClick={() => onUnblock(b, note.trim())}>
              Unblock {b.identity}
            </Button>
          </div>
        ) : (
          <div>
            <Button type="button" variant="quiet" onClick={() => setLifting(true)}>
              Lift
            </Button>
          </div>
        )
      ) : null}
    </li>
  );
}
