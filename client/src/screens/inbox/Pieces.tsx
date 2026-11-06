import { useState } from 'react';
import type { Pieces as PiecesData } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;

// The writing gate (seshat#42): a piece she marked for review waits for
// your yes; an approved one goes to the reader, which makes a Substack
// draft; you press Publish on Substack yourself.
export function Pieces({ residentName, pieces, onReview, onOpen }: { residentName: string; pieces: PiecesData; onReview?: (path: string, decision: 'approve' | 'decline', note: string) => void; onOpen?: (path: string) => void }) {
  const { for_review, approved, drafted } = pieces;
  if (for_review.length + approved.length + drafted.length === 0) return null;
  return (
    <section aria-label="Writing" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
      <h2 style={{ margin: 0, fontSize: 16, lineHeight: '22px', fontWeight: 600 }}>{residentName}’s writing</h2>
      {for_review.map((p) => (
        <ForReview key={p.path} piece={p} onReview={onReview} onOpen={onOpen} />
      ))}
      {approved.map((p) => (
        <Card key={p.path} title={p.title ?? p.path}>
          <p style={muted}>Approved. The reader makes a Substack draft of it next; it is never published without you.</p>
        </Card>
      ))}
      {drafted.map((p) => (
        <Card key={p.path} title={p.title ?? p.path}>
          <p style={muted}>A Substack draft is ready. Read it there and press Publish when it looks right; the link comes back to the piece.</p>
          {p.draft_url ? (
            <a href={p.draft_url} target="_blank" rel="noreferrer" style={{ fontSize: 15 }}>
              Open the draft on Substack
            </a>
          ) : null}
        </Card>
      ))}
    </section>
  );
}

function ForReview({ piece, onReview, onOpen }: { piece: PiecesData['for_review'][number]; onReview?: (path: string, decision: 'approve' | 'decline', note: string) => void; onOpen?: (path: string) => void }) {
  const [note, setNote] = useState('');
  const ready = note.trim() !== '';
  return (
    <Card title={`For review: ${piece.title ?? piece.path}`}>
      {piece.last ? <p style={muted}>Last time you {piece.last.state === 'declined' ? 'declined it' : 'approved it'}: {piece.last.note}</p> : null}
      {onOpen ? (
        <Button variant="quiet" onClick={() => onOpen(piece.path)}>
          Read it
        </Button>
      ) : null}
      <Field label="Your note (required)" value={note} onChange={(e) => setNote(e.target.value)} />
      <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
        <Button variant="primary" disabled={!ready} onClick={() => onReview?.(piece.path, 'approve', note.trim())}>
          Approve
        </Button>
        <Button variant="quiet" disabled={!ready} onClick={() => onReview?.(piece.path, 'decline', note.trim())}>
          Decline
        </Button>
      </div>
    </Card>
  );
}
