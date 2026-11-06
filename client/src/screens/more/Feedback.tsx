import { useState } from 'react';
import type { FeedbackReport } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const STATUS: Record<string, string> = { new: 'new', in_work: 'being worked on', resolved: 'resolved', closed: 'closed' };

// Report a problem or suggest a feature (gaia#20): to the platform team,
// the operator's triage list and Lily, said where it goes before it goes.
// Never about your resident's conduct toward you; that is not this.
export function Feedback({ mine, onFile }: { mine: FeedbackReport[]; onFile?: (r: { kind: 'bug' | 'feature_request'; surface: string; body: string; trace_id: string | null }) => Promise<unknown> }) {
  const [kind, setKind] = useState<'bug' | 'feature_request'>('bug');
  const [surface, setSurface] = useState('');
  const [body, setBody] = useState('');
  const [trace, setTrace] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <Card title="Report a problem or suggest a feature">
      <p style={muted}>It goes to the platform team: the operator&apos;s triage list and Lily, who reads every one the same day. Say only what you want them to read.</p>
      <div role="group" aria-label="Kind" style={{ display: 'flex', gap: 'var(--space-2)' }}>
        <Button variant={kind === 'bug' ? 'primary' : 'quiet'} aria-pressed={kind === 'bug'} onClick={() => setKind('bug')}>
          A problem
        </Button>
        <Button variant={kind === 'feature_request' ? 'primary' : 'quiet'} aria-pressed={kind === 'feature_request'} onClick={() => setKind('feature_request')}>
          A feature
        </Button>
      </div>
      <Field label="Where (a screen, a moment)" value={surface} onChange={(e) => setSurface(e.target.value)} />
      <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
        <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>In your words</span>
        <textarea aria-label="In your words" value={body} rows={5} onChange={(e) => setBody(e.target.value)} style={{ font: 'inherit', fontSize: 15, padding: 'var(--space-2)' }} />
      </label>
      <Field label="Trace id, if a screen showed one (optional)" value={trace} onChange={(e) => setTrace(e.target.value)} />
      <Button
        variant="primary"
        disabled={body.trim() === ''}
        onClick={() =>
          onFile?.({ kind, surface: surface.trim(), body: body.trim(), trace_id: trace.trim() || null })
            .then(() => {
              setBody('');
              setSurface('');
              setTrace('');
              setSaid('Sent to the platform team.');
            })
            .catch((e: unknown) => setSaid(e instanceof Error ? e.message : 'That did not send.'))
        }
      >
        Send to the platform team
      </Button>
      {said ? <p role="status" style={muted}>{said}</p> : null}
      {mine.length ? (
        <ul aria-label="Your reports" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          {mine.map((r) => (
            <li key={r.number} style={muted}>
              #{r.number} {r.kind === 'bug' ? 'a problem' : 'a feature'}
              {r.surface ? ` on ${r.surface}` : ''}: {STATUS[r.status] ?? r.status}
              {r.note ? `, "${r.note}"` : ''}
            </li>
          ))}
        </ul>
      ) : null}
    </Card>
  );
}
