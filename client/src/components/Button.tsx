import type { ButtonHTMLAttributes } from 'react';

// The witness's hue is the only hue on controls (spec §6.15). A
// destructive action confirms by changing to its consequence, which the
// caller does by changing the label; there is no modal.
export function Button({
  variant = 'secondary',
  style,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'secondary' | 'quiet' }) {
  const primary = variant === 'primary';
  const quiet = variant === 'quiet';
  return (
    <button
      type="button"
      {...rest}
      style={{
        minHeight: 'var(--control-h-sm)',
        padding: '0 var(--space-3)',
        borderRadius: 'var(--radius-md)',
        border: quiet ? '1px solid transparent' : '1px solid var(--hairline-strong)',
        background: primary ? 'var(--witness)' : 'transparent',
        color: primary ? 'var(--on-witness)' : 'var(--witness)',
        fontFamily: 'var(--font-sans)',
        fontSize: 13,
        fontWeight: 500,
        cursor: rest.disabled ? 'not-allowed' : 'pointer',
        opacity: rest.disabled ? 0.5 : 1,
        ...style,
      }}
    />
  );
}
