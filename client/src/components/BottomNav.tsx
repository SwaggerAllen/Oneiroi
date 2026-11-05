export type Destination = 'chat' | 'memory' | 'schedule' | 'inbox' | 'more' | 'library' | 'connections' | 'ledger' | 'regression' | 'agreement';

// Chat is home; there is no dashboard (spec §10). The spec's five:
// Chat, Memory, Schedule, Inbox and More, which holds Ledger and
// Regression, so More is lit while either is open.
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
    { id: 'schedule', label: 'Schedule' },
    { id: 'inbox', label: 'Inbox' },
    { id: 'more', label: 'More' },
  ];
  const lit = ['ledger', 'regression', 'library', 'connections', 'agreement'].includes(current) ? 'more' : current;
  return (
    <nav
      aria-label="Main"
      style={{
        display: 'flex',
        borderTop: '1px solid var(--hairline)',
        background: 'var(--surface-raised)',
        position: 'sticky',
        bottom: 0,
        // Above the home indicator or gesture bar.
        paddingBottom: 'env(safe-area-inset-bottom)',
      }}
    >
      {items.map((item) => (
        <button
          key={item.id}
          type="button"
          aria-current={item.id === lit ? 'page' : undefined}
          onClick={() => onChange(item.id)}
          style={{
            flex: 1,
            minHeight: 'var(--control-h)',
            border: 'none',
            background: 'transparent',
            color: item.id === lit ? 'var(--witness)' : 'var(--ink-muted)',
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
