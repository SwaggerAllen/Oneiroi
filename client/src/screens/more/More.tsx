import type { ReactNode } from 'react';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { TopBar } from '../../components/TopBar';

export type MoreScreen =
  | 'library'
  | 'connections'
  | 'ledger'
  | 'regression'
  | 'agreement'
  | 'work'
  | 'notifications'
  | 'feedback'
  | 'operator'
  | 'waiting'
  | 'correspondence';

// More (spec §10): navigation only (the witness, 2026-11-08: "the more
// menu should be navigation items only, all functionality should be on
// its own page"). Each item opens a page of its own; nothing here acts.
// The spec gives it five collapsed groups (Library, Judgement, the
// resident, Account, Platform); until those exist it lists the pages
// that are built, Operator only for an operator.
export function More({ onOpen, operator = false }: { onOpen: (screen: MoreScreen) => void; operator?: boolean }) {
  const items: Array<{ id: MoreScreen; label: string; line: string }> = [
    { id: 'waiting', label: 'Waiting on you', line: 'Everything whose next move is yours, each opening the thing itself.' },
    { id: 'correspondence', label: 'Correspondence', line: 'Every message from outside the house and every reply, by person and by conversation.' },
    { id: 'work', label: 'Work', line: 'The work queue: what is underway, what is next, what waits on you.' },
    { id: 'agreement', label: 'Agreement', line: 'Your agreement, its switches, and who looks after them.' },
    { id: 'library', label: 'Library', line: 'Every document, the keepsakes, and your own.' },
    { id: 'connections', label: 'Connections', line: 'What holds a token: Claude Code, the reader.' },
    { id: 'ledger', label: 'Ledger', line: 'Your key, budget lines and what has been spent.' },
    { id: 'regression', label: 'Regression', line: 'Tests across models, graded blind.' },
    { id: 'notifications', label: 'Notifications', line: 'Whether this device is told when there is something for you.' },
    { id: 'feedback', label: 'Report a problem', line: 'A problem with the platform, or a feature to suggest, and what became of yours.' },
    ...(operator ? [{ id: 'operator' as const, label: 'Operator', line: 'The front door, roles, the triage desk, invites and reports.' }] : []),
  ];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="More" />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        {items.map((item) => (
          <Card key={item.id}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)' }}>
              <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>{item.line}</p>
              <Button onClick={() => onOpen(item.id)}>{item.label}</Button>
            </div>
          </Card>
        ))}
      </main>
    </div>
  );
}

// A page reached from More: its title, a line, and what it holds.
export function MorePage({ title, line, children }: { title: string; line?: string; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title={title} line={line} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>{children}</main>
    </div>
  );
}
