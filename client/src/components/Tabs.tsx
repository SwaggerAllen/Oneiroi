export function Tabs<T extends string>({
  tabs,
  current,
  onChange,
}: {
  tabs: Array<{ id: T; label: string; count?: number }>;
  current: T;
  onChange: (id: T) => void;
}) {
  return (
    <div role="tablist" style={{ display: 'flex', gap: 'var(--space-1)', overflowX: 'auto' }}>
      {tabs.map((tab) => {
        const selected = tab.id === current;
        return (
          <button
            key={tab.id}
            type="button"
            role="tab"
            aria-selected={selected}
            onClick={() => onChange(tab.id)}
            style={{
              minHeight: 'var(--control-h-sm)',
              padding: '0 var(--space-3)',
              border: 'none',
              borderBottom: selected ? '2px solid var(--witness)' : '2px solid transparent',
              background: 'transparent',
              color: selected ? 'var(--ink)' : 'var(--ink-muted)',
              fontFamily: 'var(--font-sans)',
              fontSize: 13,
              fontWeight: 500,
              whiteSpace: 'nowrap',
              cursor: 'pointer',
            }}
          >
            {tab.label}
            {tab.count !== undefined ? ` ${tab.count}` : ''}
          </button>
        );
      })}
    </div>
  );
}
