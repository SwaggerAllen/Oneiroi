import type { LibraryDocument, Pieces as PiecesData } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { TopBar } from '../../components/TopBar';
import { Pieces } from '../inbox/Pieces';

export interface DocumentPageProps {
  residentName: string;
  path: string;
  // Its row, when the library holds it (its kind, title and times).
  doc: LibraryDocument | null;
  // The kind's name as the shelf gives it.
  kindLabel?: string | null;
  content: string | null;
  // Its words could not be read (a path the library does not hold).
  missing?: boolean;
  // What waits on you about this document, if anything: a piece for
  // review, so the decision is made here, beside the words.
  pieces?: PiecesData | null;
  onReview?: (path: string, decision: 'approve' | 'decline', note: string) => void;
  // Back to its kind's list.
  onBack: () => void;
}

const meta = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;
const when = (at: string | null | undefined) => (at ? `${at.slice(0, 16).replace('T', ' ')} UTC` : 'unknown');

// A document, alone on a page of its own (#doc/<path>; the witness,
// 2026-11-08, through Lily's letter #338): its words, when it came and
// when it was last written, and, when it waits on you, the decision
// beside it. A link from anywhere (the waiting list's piece, a search
// hit) lands here.
export function DocumentPage({ residentName, path, doc, kindLabel = null, content, missing = false, pieces = null, onReview, onBack }: DocumentPageProps) {
  const mine = pieces ? { for_review: pieces.for_review.filter((p) => p.path === path), approved: pieces.approved.filter((p) => p.path === path), drafted: pieces.drafted.filter((p) => p.path === path) } : null;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title={doc?.title ?? path} line={kindLabel ? `${kindLabel} · ${path}` : path} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <div>
          <Button variant="quiet" onClick={onBack}>
            ← {kindLabel ? `All ${kindLabel.toLowerCase()}` : 'The library'}
          </Button>
        </div>
        {doc ? (
          <p style={meta}>
            Created {when(doc.created_at)} · updated {when(doc.written_at)}
            {doc.written_by ? ` by ${doc.written_by === 'resident' ? residentName : doc.written_by === 'witness' ? 'you' : doc.written_by}` : ''} · {doc.versions}{' '}
            {doc.versions === 1 ? 'version' : 'versions'}
            {doc.status ? ` · ${doc.status}` : ''}
            {doc.missing_at ? ' · missing from the repository' : ''}
          </p>
        ) : null}
        {mine ? <Pieces residentName={residentName} pieces={mine} onReview={onReview} /> : null}
        {missing ? (
          <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>The library holds nothing at {path}.</p>
        ) : content === null ? (
          <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>Reading…</p>
        ) : (
          <Card>
            <pre style={{ margin: 0, fontFamily: 'var(--font-serif)', fontSize: 15, lineHeight: '23px', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{content}</pre>
          </Card>
        )}
      </main>
    </div>
  );
}
