import { useState } from 'react';
import type { FeedbackReport } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const STATUSES = ['new', 'in_work', 'resolved', 'closed'] as const;

export interface ReportDetail extends FeedbackReport {
  failures: { at: string; level: string; component: string | null; error_kind: string | null; error_site: string | null; message: string }[];
}

// The operator's triage list (gaia#20): every platform report, narrowed
// by status, one open with the failure ring's entries for its trace id
// beside the reporter's words, and a move with a note the reporter reads.
export function Reports({ reports, open, onOpen, onMove }: { reports: FeedbackReport[]; open?: ReportDetail | null; onOpen?: (n: number) => void; onMove?: (n: number, status: string, note: string) => void }) {
  const [status, setStatus] = useState<string>('new');
  const [note, setNote] = useState('');
  const shown = status === 'all' ? reports : reports.filter((r) => r.status === status);
  return (
    <Card title="Reports">
      <div role="group" aria-label="Status" style={{ display: 'flex', gap: 'var(--space-1)', flexWrap: 'wrap' }}>
        {[...STATUSES, 'all'].map((s) => (
          <Button key={s} variant={status === s ? 'primary' : 'quiet'} aria-pressed={status === s} onClick={() => setStatus(s)}>
            {s.replace('_', ' ')}
          </Button>
        ))}
      </div>
      {shown.length === 0 ? <p style={muted}>None.</p> : null}
      <ul aria-label="Reports" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        {shown.map((r) => (
          <li key={r.number}>
            <Button variant="quiet" onClick={() => onOpen?.(r.number)}>
              #{r.number} {r.kind === 'bug' ? 'problem' : 'feature'}
              {r.surface ? ` · ${r.surface}` : ''} · {r.author_kind}
            </Button>
          </li>
        ))}
      </ul>
      {open ? (
        <div aria-label={`Report ${open.number}`} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', borderTop: '1px solid var(--hairline)', paddingTop: 'var(--space-2)' }}>
          <p style={{ margin: 0, fontSize: 15, whiteSpace: 'pre-wrap' }}>{open.body}</p>
          <p style={muted}>
            {open.status.replace('_', ' ')}
            {open.note ? `: ${open.note}` : ''}
            {open.trace_id ? ` · trace ${open.trace_id}` : ''}
          </p>
          {open.trace_id ? (
            open.failures.length ? (
              <ul aria-label="What the platform logged" style={{ margin: 0, paddingLeft: 'var(--space-4)', fontSize: 13 }}>
                {open.failures.map((f, i) => (
                  <li key={i}>
                    {f.at} {f.level} {f.component ?? ''} {f.error_kind ?? ''} {f.error_site ?? ''}: {f.message}
                  </li>
                ))}
              </ul>
            ) : (
              <p style={muted}>The failure ring holds nothing for this trace id (it keeps the last 200, and empties on a restart).</p>
            )
          ) : null}
          <Field label="A note the reporter reads (required)" value={note} onChange={(e) => setNote(e.target.value)} />
          <div style={{ display: 'flex', gap: 'var(--space-1)', flexWrap: 'wrap' }}>
            {STATUSES.filter((s) => s !== open.status).map((s) => (
              <Button key={s} disabled={note.trim() === ''} onClick={() => onMove?.(open.number, s, note.trim())}>
                Mark {s.replace('_', ' ')}
              </Button>
            ))}
          </div>
        </div>
      ) : null}
    </Card>
  );
}
