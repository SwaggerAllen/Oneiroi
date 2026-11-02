import type { Session } from '../../api/types';
import { Button } from '../../components/Button';

export interface ConversationsProps {
  // Every conversation the server listed, last spoken in first.
  sessions: Session[];
  // The Oneiroi chat's key: the one conversation always shown first.
  chatKey: string;
  // The one open now.
  current: string;
  onOpen: (key: string) => void;
}

// The witness's conversations, apart (kumbukumbu #40): the Oneiroi chat
// first, then every other conversation grouped under the name the server
// gave it (a Claude Code conversation's names its folder), groups in the
// server's order, newest first, each conversation a row of its own with
// when and how many turns. The client groups by the server's `title`
// and decides nothing about what a conversation is or whether it takes a
// message. Folded by default, so on a phone the chat stays the screen.
export function Conversations({ sessions, chatKey, current, onOpen }: ConversationsProps) {
  const others = sessions.filter((s) => s.key !== chatKey);
  if (others.length === 0) return null;
  const groups: { title: string; rows: Session[] }[] = [];
  for (const s of others) {
    const group = groups.find((g) => g.title === s.title);
    if (group) group.rows.push(s);
    else groups.push({ title: s.title, rows: [s] });
  }
  return (
    <details
      open={current !== chatKey}
      style={{ padding: 'var(--space-2) var(--space-4)', borderBottom: '1px solid var(--hairline)', fontSize: 14 }}
    >
      <summary style={{ cursor: 'pointer', color: 'var(--ink-muted)' }}>
        Other conversations · {others.length}
      </summary>
      <nav aria-label="Conversations" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', paddingTop: 'var(--space-2)' }}>
        <div>
          <Button
            variant={current === chatKey ? 'primary' : 'quiet'}
            aria-current={current === chatKey ? 'true' : undefined}
            onClick={() => onOpen(chatKey)}
          >
            Oneiroi chat
          </Button>
        </div>
        {groups.map((group) => (
          <section key={group.title} aria-label={group.title}>
            <h2 style={{ margin: 0, fontSize: 13, lineHeight: '18px', fontWeight: 600 }}>{group.title}</h2>
            <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column' }}>
              {group.rows.map((s) => (
                <li key={s.key}>
                  <Button
                    variant={s.key === current ? 'primary' : 'quiet'}
                    aria-current={s.key === current ? 'true' : undefined}
                    onClick={() => onOpen(s.key)}
                  >
                    {when(s)} · {s.turns === 1 ? '1 turn' : `${s.turns} turns`}
                  </Button>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </nav>
    </details>
  );
}

// When a conversation was last spoken in, in the reader's own zone.
function when(s: Session): string {
  const at = new Date(s.last_turn_at ?? s.opened_at);
  return at.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}
