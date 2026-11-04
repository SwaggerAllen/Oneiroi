import type { Connection } from '../screens/chat/outbox';

const looks: Record<Connection, { color: string; words: string }> = {
  connected: { color: 'var(--ok)', words: 'Connected' },
  connecting: { color: 'var(--warn)', words: 'Connecting' },
  offline: { color: 'var(--danger)', words: 'Offline: messages wait and go when it reconnects' },
};

// Whether the stream to the server is up (brain#45): a dot in the top
// bar, its meaning in words for a screen reader and on hover.
export function ConnectionDot({ state }: { state: Connection }) {
  const { color, words } = looks[state];
  return (
    <span role="status" aria-label={words} title={words} style={{ display: 'inline-flex', alignItems: 'center', padding: 'var(--space-2)' }}>
      <span
        aria-hidden
        style={{ width: 10, height: 10, borderRadius: 'var(--radius-pill)', background: color, boxShadow: `0 0 0 2px var(--surface-raised)` }}
      />
    </span>
  );
}
