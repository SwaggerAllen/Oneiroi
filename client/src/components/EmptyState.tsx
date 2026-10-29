export function EmptyState({ text }: { text: string }) {
  return (
    <p
      style={{
        margin: 0,
        padding: 'var(--space-5) var(--space-4)',
        textAlign: 'center',
        color: 'var(--ink-muted)',
        fontSize: 15,
        lineHeight: '22px',
      }}
    >
      {text}
    </p>
  );
}
