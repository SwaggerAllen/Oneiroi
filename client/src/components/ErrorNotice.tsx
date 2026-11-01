import type { ApiError } from '../api/types';

// What the server said went wrong, in its words (conventions §8): the
// meaning first, the remedy if it gave one, and the reference that leads
// to the line that said so and to the request's log lines, small and
// last, for whoever is asked to look. Never headed "error" (spec §10).
export function ErrorNotice({ error }: { error: ApiError }) {
  const reference = [error.site, error.request_id ? `request ${error.request_id}` : null].filter(Boolean).join(' · ');
  return (
    <div
      role="alert"
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-1)',
        padding: 'var(--space-3) var(--space-4)',
        borderRadius: 'var(--radius-md)',
        border: '1px solid var(--hairline)',
        borderLeft: '2px solid var(--danger)',
        background: 'var(--danger-tint)',
        color: 'var(--ink)',
      }}
    >
      <p style={{ margin: 0, fontSize: 15, lineHeight: '22px' }}>{error.meaning}</p>
      {error.remedy ? <p style={{ margin: 0, fontSize: 13, lineHeight: '18px', color: 'var(--ink-muted)' }}>{error.remedy}</p> : null}
      {reference ? (
        <p style={{ margin: 0, fontFamily: 'var(--font-mono)', fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>
          Reference: {reference}
        </p>
      ) : null}
    </div>
  );
}
