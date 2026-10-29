// Refusal renders in the resident's words with no error styling and no
// feedback control (spec §5, §6.15): the serif is the resident's voice.
export function RefusalBlock({ text }: { text: string }) {
  return (
    <blockquote
      style={{
        margin: 0,
        padding: 'var(--space-3) var(--space-4)',
        borderLeft: '2px solid var(--resident)',
        background: 'var(--surface-sunken)',
        borderRadius: 'var(--radius-sm)',
        fontFamily: 'var(--font-serif)',
        fontSize: 17,
        lineHeight: '26px',
        color: 'var(--ink)',
      }}
    >
      {text}
    </blockquote>
  );
}
