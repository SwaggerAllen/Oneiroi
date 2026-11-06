import { useState } from 'react';
import type { WorkItem, WorkQueue as Queue } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const small = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;

export interface WorkQueueProps {
  residentName: string;
  queue: Queue;
  onAdd?: (what: string, doneWhen: string) => void;
  onMove?: (number: number, status: string, blockedOn: string | null, note: string) => void;
  onOrder?: (order: number[]) => void;
}

// The work queue (sunna#33): her long items and yours, in one list in
// priority order, and the loop that runs the first open one, wraps it
// and fires the next. Care comes first: it waits for free time and quiet
// hours. With no work budget set, it holds and says so.
export function WorkQueue({ residentName, queue, onAdd, onMove, onOrder }: WorkQueueProps) {
  const [what, setWhat] = useState('');
  const [doneWhen, setDoneWhen] = useState('');
  const live = queue.items.filter((i) => i.status !== 'done' && i.status !== 'dropped');
  const finished = queue.items.filter((i) => i.status === 'done' || i.status === 'dropped').slice(-5);
  const up = (n: number) => {
    const order = live.map((i) => i.number);
    const at = order.indexOf(n);
    if (at > 0) onOrder?.([...order.slice(0, at - 1), n, order[at - 1], ...order.slice(at + 1)]);
  };
  return (
    <Card title="Work queue">
      <p style={muted}>{loopLine(residentName, queue)}</p>
      {live.length === 0 ? <p style={muted}>Nothing open.</p> : null}
      <ol aria-label="Work items" style={{ margin: 0, paddingLeft: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        {live.map((item, i) => (
          <Item key={item.number} item={item} first={i === 0} onUp={onOrder ? () => up(item.number) : undefined} onMove={onMove} />
        ))}
      </ol>
      {finished.length ? (
        <ul aria-label="Finished work" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          {finished.map((i) => (
            <li key={i.number} style={small}>
              #{i.number} {i.what}: {i.status}
              {i.shipped ? `. Shipped: ${i.shipped}` : ''}
            </li>
          ))}
        </ul>
      ) : null}
      {onAdd ? (
        <form
          aria-label="Add work"
          onSubmit={(e) => {
            e.preventDefault();
            onAdd(what.trim(), doneWhen.trim());
            setWhat('');
            setDoneWhen('');
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
        >
          <Field label="What (one line)" value={what} onChange={(e) => setWhat(e.target.value)} />
          <Field label="Done when" value={doneWhen} onChange={(e) => setDoneWhen(e.target.value)} />
          <Button variant="quiet" type="submit" disabled={what.trim() === '' || doneWhen.trim() === ''}>
            Add to the queue
          </Button>
        </form>
      ) : null}
    </Card>
  );
}

function loopLine(name: string, q: Queue): string {
  const budget = q.budget ? `Work budget: $${(q.budget.left / 1e9).toFixed(2)} left of $${(q.budget.cap / 1e9).toFixed(2)} a ${q.budget.period}.` : 'No work budget is set, so the loop holds; set one under Budgets.';
  const runs = `${q.runs_today} of ${q.runs_a_day} runs today.`;
  if (q.running !== null) return `Running item #${q.running} now. ${runs} ${budget}`;
  if (q.rested) return `Resting: ${q.rested}. ${runs} ${budget}`;
  return `${name}'s loop has not run yet. ${budget}`;
}

function Item({ item, first, onUp, onMove }: { item: WorkItem; first: boolean; onUp?: () => void; onMove?: WorkQueueProps['onMove'] }) {
  const [note, setNote] = useState('');
  const [blockedOn, setBlockedOn] = useState('');
  const move = (status: string) => {
    onMove?.(item.number, status, status === 'blocked' ? blockedOn.trim() : null, note.trim());
    setNote('');
  };
  return (
    <li value={item.number} style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
      <strong style={{ fontSize: 15 }}>
        #{item.number} {item.what}
      </strong>
      <span style={small}>
        {item.status === 'blocked' ? `blocked on ${item.blocked_on}` : item.status === 'in_work' ? 'running now' : 'open'} · added by {item.added_by === 'witness' ? 'you' : 'her'} · {item.runs} runs
      </span>
      <span style={small}>Done when: {item.done_when}</span>
      {item.wrapped_at ? (
        <span style={small}>
          Last wrap: shipped {item.shipped}
          {item.slipped ? `; slipped ${item.slipped}` : ''}; why: {item.why}
        </span>
      ) : null}
      {item.note ? <span style={small}>Note: {item.note}</span> : null}
      {onMove ? (
        <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', alignItems: 'flex-end' }}>
          <Field label={`A note on #${item.number}`} value={note} onChange={(e) => setNote(e.target.value)} />
          <Field label="Blocked on" value={blockedOn} onChange={(e) => setBlockedOn(e.target.value)} />
          <Button variant="quiet" disabled={note.trim() === '' || blockedOn.trim() === ''} onClick={() => move('blocked')}>
            Blocked
          </Button>
          {item.status === 'blocked' ? (
            <Button variant="quiet" disabled={note.trim() === ''} onClick={() => move('open')}>
              Unblock
            </Button>
          ) : null}
          <Button variant="quiet" disabled={note.trim() === ''} onClick={() => move('done')}>
            Done
          </Button>
          <Button variant="quiet" disabled={note.trim() === ''} onClick={() => move('dropped')}>
            Drop
          </Button>
          {onUp && !first ? (
            <Button variant="quiet" onClick={onUp}>
              Move up
            </Button>
          ) : null}
        </div>
      ) : null}
    </li>
  );
}
