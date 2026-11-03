import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { TopBar } from '../../components/TopBar';

export type MoreScreen = 'library' | 'connections' | 'ledger' | 'regression';

// More (spec §10): the screens that are not one of the four daily
// destinations. The spec gives it five collapsed groups (Library,
// Judgement, the resident, Account, Platform); until those exist it
// lists the screens that are built.
export function More({ onOpen }: { onOpen: (screen: MoreScreen) => void }) {
  const items: Array<{ id: MoreScreen; label: string; line: string }> = [
    { id: 'library', label: 'Library', line: 'Every document, the keepsakes, and your own.' },
    { id: 'connections', label: 'Connections', line: 'What holds a token: Claude Code, the reader.' },
    { id: 'ledger', label: 'Ledger', line: 'Your key, budget lines and what has been spent.' },
    { id: 'regression', label: 'Regression', line: 'Tests across models, graded blind.' },
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
