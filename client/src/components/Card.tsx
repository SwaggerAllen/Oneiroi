import type { ReactNode } from 'react';

export function Card({ children, title }: { children: ReactNode; title?: string }) {
  return (
    <section
      style={{
        background: 'var(--surface-raised)',
        border: '1px solid var(--hairline)',
        borderRadius: 'var(--radius-lg)',
        padding: 'var(--space-4)',
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-3)',
      }}
    >
      {title ? (
        <h2 style={{ margin: 0, fontSize: 16, lineHeight: '22px', fontWeight: 600 }}>{title}</h2>
      ) : null}
      {children}
    </section>
  );
}
