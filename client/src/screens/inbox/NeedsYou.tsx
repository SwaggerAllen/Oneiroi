import { useState } from 'react';
import type { CorrespondenceMessage, Correspondent, Reply } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

export interface GateActions {
  onDecideMessage?: (number: number, approve: boolean, note: string, trust: boolean) => void;
  onDecideReply?: (number: number, approve: boolean, note: string) => void;
  onMarkSent?: (number: number, url: string | null) => void;
  onDistrust?: (c: Correspondent, note: string) => void;
}

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const meta = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;
const when = (at: string) => `${at.slice(0, 16).replace('T', ' ')} UTC`;

function firstLine(text: string): string {
  const line = text.split('\n').find((l) => l.trim() !== '') ?? '';
  return line.length > 140 ? `${line.slice(0, 140)}…` : line;
}

// Needs you (spec §10, xenia #12, #13): the messages that wait for your
// reading, the replies that wait for your yes, and the approved replies
// not yet sent. Every decision carries a note, which the resident reads
// first; nothing here is decided without one.
export function NeedsYou({
  residentName,
  pending,
  drafted,
  approved,
  actions,
}: {
  residentName: string;
  pending: CorrespondenceMessage[];
  drafted: Reply[];
  approved: Reply[];
  actions: GateActions;
}) {
  const nothing = pending.length + drafted.length + approved.length === 0;
  return (
    <Card title="Needs you">
      {nothing ? (
        <p style={muted}>Nothing waits on you.</p>
      ) : (
        <ol aria-label="Needs you" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          {pending.map((m) => (
            <PendingMessage key={`m${m.number}`} residentName={residentName} message={m} onDecide={actions.onDecideMessage} />
          ))}
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

function PendingMessage({
  residentName,
  message: m,
  onDecide,
}: {
  residentName: string;
  message: CorrespondenceMessage;
  onDecide?: GateActions['onDecideMessage'];
}) {
  const [note, setNote] = useState('');
  const [trust, setTrust] = useState(false);
  const from = m.sender_name ? `${m.sender_name} <${m.sender}>` : m.sender;
  return (
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', borderTop: '1px solid var(--hairline)', paddingTop: 'var(--space-3)' }}>
      <p style={meta}>
        Message #{m.number} · {m.platform} · from {from} · {when(m.sent_at)}
        {m.verified ? '' : ' · sender not verified'}
      </p>
      {m.subject ? <p style={{ margin: 0, fontSize: 15, fontWeight: 600 }}>{m.subject}</p> : null}
      <details>
        <summary style={{ cursor: 'pointer', fontSize: 15 }}>{firstLine(m.text)}</summary>
        <p style={{ margin: 'var(--space-2) 0 0', fontSize: 15, whiteSpace: 'pre-wrap' }}>{m.text}</p>
      </details>
      {onDecide ? (
        <form
          aria-label={`Decide message ${m.number}`}
          onSubmit={(e) => e.preventDefault()}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
        >
          <Field label={`Your note to ${residentName}`} value={note} onChange={(e) => setNote(e.target.value)} />
          <label style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center', fontSize: 13 }}>
            <input type="checkbox" checked={trust} disabled={!m.verified} onChange={(e) => setTrust(e.target.checked)} />
            {m.verified ? `Trust ${m.sender} on ${m.platform} from now on` : 'Only a verified sender can be trusted'}
          </label>
          <div style={row}>
            <Button variant="primary" type="button" disabled={note.trim() === ''} onClick={() => onDecide(m.number, true, note.trim(), trust)}>
              Let it through
            </Button>
            <Button type="button" disabled={note.trim() === ''} onClick={() => onDecide(m.number, false, note.trim(), false)}>
              Keep it out
            </Button>
          </div>
        </form>
      ) : null}
    </li>
  );
}

function DraftedReply({ residentName, reply: r, onDecide }: { residentName: string; reply: Reply; onDecide?: GateActions['onDecideReply'] }) {
  const [note, setNote] = useState('');
  return (
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', borderTop: '1px solid var(--hairline)', paddingTop: 'var(--space-3)' }}>
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
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', borderTop: '1px solid var(--hairline)', paddingTop: 'var(--space-3)' }}>
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

// The trusted list (xenia #12): whose verified messages reach the
// resident without your reading. Removing one asks for a note, in place.
export function Trusted({
  residentName,
  correspondents,
  onDistrust,
}: {
  residentName: string;
  correspondents: Correspondent[];
  onDistrust?: GateActions['onDistrust'];
}) {
  return (
    <Card title="Trusted people">
      <p style={muted}>Their messages reach {residentName} without your reading, when the sender is verified. Everyone else waits for you.</p>
      {correspondents.length === 0 ? (
        <p style={muted}>Nobody yet. Trust someone when you let their message through.</p>
      ) : (
        <ul aria-label="Trusted people" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          {correspondents.map((c) => (
            <TrustedRow key={`${c.platform}:${c.identity}`} correspondent={c} onDistrust={onDistrust} />
          ))}
        </ul>
      )}
    </Card>
  );
}

function TrustedRow({ correspondent: c, onDistrust }: { correspondent: Correspondent; onDistrust?: GateActions['onDistrust'] }) {
  const [removing, setRemoving] = useState(false);
  const [note, setNote] = useState('');
  return (
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', fontSize: 15 }}>
      <span>
        {c.name ? `${c.name} · ` : ''}
        {c.identity} <span style={{ color: 'var(--ink-muted)' }}>on {c.platform}</span>
      </span>
      {onDistrust ? (
        removing ? (
          <div style={row}>
            <Field label="Why" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button type="button" disabled={note.trim() === ''} onClick={() => onDistrust(c, note.trim())}>
              Stop trusting {c.identity}
            </Button>
          </div>
        ) : (
          <div>
            <Button type="button" variant="quiet" onClick={() => setRemoving(true)}>
              Remove
            </Button>
          </div>
        )
      ) : null}
    </li>
  );
}
