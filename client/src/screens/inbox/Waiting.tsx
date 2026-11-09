import { useState } from 'react';
import { Card } from '../../components/Card';
import { age, type WaitingEntry } from './queue';
import { libraryHash } from '../library/route';

const href = (where: WaitingEntry['where']) => ('anchor' in where ? `#${where.anchor}` : 'doc' in where ? `#${libraryHash({ doc: where.doc })}` : '#');

// Waiting on you (screens/inbox.md): the server's `needs_you` list,
// oldest first, each a link to where its decision is made. The card
// itself has no button: the queue shows, the click is his, always.
export function Waiting({ entries, now: fixed, onOpen }: { entries: WaitingEntry[]; now?: number; onOpen?: (where: WaitingEntry['where']) => void }) {
  const [opened] = useState(() => Date.now());
  const now = fixed ?? opened;
  return (
    <Card title="Waiting on you">
      {entries.length === 0 ? (
        <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>Nothing waits on you.</p>
      ) : (
        <>
          <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-muted)' }}>Oldest first. Nothing here is sent or decided until you do it.</p>
          <ol aria-label="Waiting on you" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
            {entries.map((e) => {
              const long = e.long;
              return (
                <li key={e.key} style={{ fontSize: 15, display: 'flex', flexDirection: 'column', gap: 2 }}>
                  {onOpen ? (
                    <a
                      href={href(e.where)}
                      onClick={(ev) => {
                        ev.preventDefault();
                        onOpen(e.where);
                      }}
                    >
                      {e.what}
                    </a>
                  ) : 'anchor' in e.where || 'doc' in e.where ? (
                    <a href={href(e.where)}>{e.what}</a>
                  ) : (
                    <span>{e.what}</span>
                  )}
                  <span style={{ fontSize: 13, color: long ? 'var(--witness)' : 'var(--ink-muted)', fontWeight: long ? 500 : 400 }}>
                    waiting {age(e.since, now)}
                    {long ? ', a long time' : ''}
                    {'screen' in e.where ? ` · on the ${e.where.screen} screen` : ''}
                  </span>
                </li>
              );
            })}
          </ol>
        </>
      )}
    </Card>
  );
}
