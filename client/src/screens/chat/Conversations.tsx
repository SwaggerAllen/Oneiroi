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

// The witness's conversations, apart (kumbukumbu#40): the Oneiroi chat
// first, then every other conversation grouped under the name the server
// gave it (a Claude Code conversation's names its folder), groups in the
// server's order, newest first, each conversation a row of its own with
// when and how many turns. The client groups by the server's `title`
// and decides nothing about what a conversation is or whether it takes a
// message. The chat opens and closes it as a panel from a button in its
// top bar ("Conversations · N"): folded under the top bar as a grey line,
// the witness never found it.
export function Conversations({ sessions, chatKey, current, onOpen }: ConversationsProps) {
  const groups: { title: string; rows: Session[] }[] = [];
  for (const s of sessions) {
    if (s.key === chatKey) continue;
    const group = groups.find((g) => g.title === s.title);
    if (group) group.rows.push(s);
    else groups.push({ title: s.title, rows: [s] });
  }
  return (
    <nav aria-label="Conversations" style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)', padding: 'var(--space-3) var(--space-4)', fontSize: 14 }}>
      <h2 style={{ margin: 0, fontSize: 16, lineHeight: '22px', fontWeight: 600 }}>Conversations</h2>
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
          <h3 style={{ margin: 0, fontSize: 13, lineHeight: '18px', fontWeight: 600 }}>{group.title}</h3>
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
  );
}

// When a conversation was last spoken in, in the reader's own zone.
function when(s: Session): string {
  const at = new Date(s.last_turn_at ?? s.opened_at);
  return at.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}
