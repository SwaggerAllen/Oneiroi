import { useState } from 'react';
import type { Ask } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// The resident's asks of you (agathos-daimon#35): leave for an act, which
// you approve or decline, and a tool she lacked, which you note; it grants
// nothing. Your answer reaches her free time as a letter.
export function Asks({ residentName, asks, onAnswer }: { residentName: string; asks: Ask[]; onAnswer?: (number: number, decision: 'approve' | 'decline' | 'noted', note: string) => void }) {
  const open = asks.filter((a) => a.decision === null);
  const answered = asks.filter((a) => a.decision !== null).slice(0, 5);
  if (asks.length === 0) return null;
  return (
    <section aria-label="Asks" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
      <h2 style={{ margin: 0, fontSize: 16, lineHeight: '22px', fontWeight: 600 }}>{residentName} asks</h2>
      {open.length === 0 ? <p style={muted}>Nothing waiting on you.</p> : null}
      {open.map((a) => (
        <OpenAsk key={a.number} ask={a} onAnswer={onAnswer} />
      ))}
      {answered.length ? (
        <ul aria-label="Answered asks" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          {answered.map((a) => (
            <li key={a.number} style={muted}>
              #{a.number} {a.subject}: {a.decision}
              {a.note ? `, ${a.note}` : ''}
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}

function OpenAsk({ ask, onAnswer }: { ask: Ask; onAnswer?: (number: number, decision: 'approve' | 'decline' | 'noted', note: string) => void }) {
  const [note, setNote] = useState('');
  const ready = note.trim() !== '';
  return (
    <Card title={ask.kind === 'act' ? `May I: ${ask.subject}` : `A tool: ${ask.subject}`}>
      <p style={muted}>Why: {ask.why}</p>
      {ask.kind === 'tool' ? <p style={muted}>Noting it grants nothing; it records that you read it.</p> : null}
      <Field label="Your note (required)" value={note} onChange={(e) => setNote(e.target.value)} />
      <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
        {ask.kind === 'act' ? (
          <>
            <Button variant="primary" disabled={!ready} onClick={() => onAnswer?.(ask.number, 'approve', note.trim())}>
              Approve
            </Button>
            <Button variant="quiet" disabled={!ready} onClick={() => onAnswer?.(ask.number, 'decline', note.trim())}>
              Decline
            </Button>
          </>
        ) : (
          <Button disabled={!ready} onClick={() => onAnswer?.(ask.number, 'noted', note.trim())}>
            Noted
          </Button>
        )}
      </div>
    </Card>
  );
}
