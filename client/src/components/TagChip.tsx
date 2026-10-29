export function TagChip({ slug, state = 'active' }: { slug: string; state?: string }) {
  const muted = state !== 'active';
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '0 var(--space-2)',
        borderRadius: 'var(--radius-pill)',
        border: '1px solid var(--hairline-strong)',
        fontFamily: 'var(--font-mono)',
        fontSize: 12,
        lineHeight: '20px',
        color: muted ? 'var(--ink-faint)' : 'var(--ink)',
        textDecoration: state === 'retired' ? 'line-through' : 'none',
      }}
    >
      {slug}
      {state === 'proposed' ? ' (proposed)' : ''}
    </span>
  );
}
