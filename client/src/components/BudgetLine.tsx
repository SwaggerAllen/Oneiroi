import type { BudgetLine as Line } from '../api/types';

// A line with its spend; "no limit" is a line that has none (nisaba #11).
export function BudgetLine({ line }: { line: Line }) {
  const cap = line.cap === null ? 'no limit' : `$${line.cap} a ${line.period}`;
  const over = line.exceeded;
  return (
    <div
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'baseline',
        padding: 'var(--space-2) 0',
        borderBottom: '1px solid var(--hairline)',
        fontSize: 15,
      }}
    >
      <span>{line.purpose}</span>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: 13, color: over ? 'var(--warn)' : 'var(--ink-muted)' }}>
        ${line.spent} of {cap}
        {over ? ', stopped' : ''}
      </span>
    </div>
  );
}
