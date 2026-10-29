export type Destination = 'chat' | 'memory' | 'ledger';

// Chat is home; there is no dashboard (spec §10). Three of the five
// destinations exist in this phase.
export function BottomNav({
  current,
  onChange,
}: {
  current: Destination;
  onChange: (destination: Destination) => void;
}) {
  const items: Array<{ id: Destination; label: string }> = [
    { id: 'chat', label: 'Chat' },
    { id: 'memory', label: 'Memory' },
    { id: 'ledger', label: 'Ledger' },
  ];
  return (
    <nav
      aria-label="Main"
      style={{
        display: 'flex',
        borderTop: '1px solid var(--hairline)',
        background: 'var(--surface-raised)',
        position: 'sticky',
        bottom: 0,
      }}
    >
      {items.map((item) => (
        <button
          key={item.id}
          type="button"
          aria-current={item.id === current ? 'page' : undefined}
          onClick={() => onChange(item.id)}
          style={{
            flex: 1,
            minHeight: 'var(--control-h)',
            border: 'none',
            background: 'transparent',
            color: item.id === current ? 'var(--steward)' : 'var(--ink-muted)',
            fontFamily: 'var(--font-sans)',
            fontSize: 13,
            fontWeight: 500,
            cursor: 'pointer',
          }}
        >
          {item.label}
        </button>
      ))}
    </nav>
  );
}
