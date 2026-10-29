import type { ReactNode } from 'react';

export function TopBar({ title, line, right }: { title: string; line?: string; right?: ReactNode }) {
  return (
    <header
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        minHeight: 'var(--control-h)',
        padding: '0 var(--space-4)',
        borderBottom: '1px solid var(--hairline)',
        background: 'var(--surface-raised)',
        position: 'sticky',
        top: 0,
      }}
    >
      <div>
        <h1 style={{ margin: 0, fontSize: 20, lineHeight: '26px', fontWeight: 600 }}>{title}</h1>
        {line ? (
          <p style={{ margin: 0, fontSize: 12, lineHeight: '16px', color: 'var(--ink-muted)' }}>{line}</p>
        ) : null}
      </div>
      {right}
    </header>
  );
}
