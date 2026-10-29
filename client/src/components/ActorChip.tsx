import type { Actor } from '../api/types';

// Attribute everything with an actor chip and a model slug (spec §6.15):
// the actor hues are reserved for this, never used alone on a control.
const hue: Record<string, string> = {
  steward: 'steward',
  resident: 'resident',
  judge: 'judge',
  hands: 'hands',
};

export function ActorChip({ actor, name }: { actor: Actor; name?: string }) {
  const kind = actor.kind ?? 'platform';
  const colour = hue[kind] ?? 'ink-muted';
  const label = name ?? (kind === 'steward' ? 'you' : kind);
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 'var(--space-1)',
        fontSize: 13,
        lineHeight: '18px',
        fontWeight: 500,
        color: `var(--${colour})`,
        fontFamily: 'var(--font-sans)',
      }}
    >
      <span
        aria-hidden="true"
        style={{
          width: 8,
          height: 8,
          borderRadius: 'var(--radius-pill)',
          background: `var(--${colour})`,
        }}
      />
      {label}
      {actor.model ? (
        <code style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--ink-faint)' }}>
          {actor.model}
        </code>
      ) : null}
    </span>
  );
}
