import tokens from '../tokens.json';

// The one component the skeleton ships: every colour token on both
// grounds, so the storybook build renders something real and the token
// file is read by code from the first commit rather than copied by hand.
export function Swatch() {
  return (
    <div style={{ padding: 'var(--space-4)', fontFamily: 'var(--font-sans)' }}>
      <h1 style={{ fontSize: 20, lineHeight: '26px', fontWeight: 600, margin: 0 }}>
        {tokens.name} tokens
      </h1>
      <ul style={{ listStyle: 'none', padding: 0, margin: 'var(--space-4) 0 0' }}>
        {tokens.color.tokens.map((c) => (
          <li
            key={c.name}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 'var(--space-3)',
              minHeight: 'var(--control-h)',
              borderBottom: '1px solid var(--hairline)',
            }}
          >
            <span
              aria-hidden="true"
              style={{
                width: 32,
                height: 32,
                borderRadius: 'var(--radius-sm)',
                background: `var(--${c.name})`,
                border: '1px solid var(--hairline-strong)',
              }}
            />
            <code style={{ fontFamily: 'var(--font-mono)', fontSize: 13 }}>{c.name}</code>
            <span style={{ color: 'var(--ink-muted)', fontSize: 13 }}>{c.usage}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
