import type { InputHTMLAttributes } from 'react';

export function Field({ label, ...rest }: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
      <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>{label}</span>
      <input
        {...rest}
        style={{
          minHeight: 'var(--control-h)',
          padding: '0 var(--space-3)',
          borderRadius: 'var(--radius-md)',
          border: '1px solid var(--hairline)',
          background: 'var(--surface-raised)',
          color: 'var(--ink)',
          fontFamily: 'var(--font-sans)',
          fontSize: 15,
        }}
      />
    </label>
  );
}
