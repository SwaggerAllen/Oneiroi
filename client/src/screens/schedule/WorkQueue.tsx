import { useState } from 'react';
import type { WorkItem, WorkQueue as Queue } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { TopBar } from '../../components/TopBar';
import { Field } from '../../components/Field';

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const small = { margin: 0, fontSize: 13, color: 'var(--ink-muted)' } as const;

export interface WorkQueueProps {
  residentName: string;
  queue: Queue;
  onAdd?: (what: string, doneWhen: string) => void;
  onMove?: (number: number, status: string, blockedOn: string | null, note: string) => void;
  onOrder?: (order: number[]) => void;
  // The work line by hand (sunna#43): arm it for a batch, or turn it off.
  onArm?: () => void;
  onDisarm?: () => void;
}

// The work queue (sunna#33): her long items and yours, in one list in
// priority order, and the loop that runs the first open one, wraps it
// and fires the next. Care comes first: it waits for free time and quiet
// hours.
// The queue's own page under More (sunna#38): it outgrew the schedule,
// where it covered the schedule's own cards.
export function WorkPage(props: WorkQueueProps) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Work" line={`${props.residentName}'s queue: underway, next, and waiting on you`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <WorkQueue {...props} />
      </main>
    </div>
  );
}

export function WorkQueue({ residentName, queue, onAdd, onMove, onOrder, onArm, onDisarm }: WorkQueueProps) {
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
      {onArm && !queue.armed && live.some((i) => i.status === 'open') ? (
        <div>
          <Button variant="primary" onClick={onArm}>
            Arm the work line
          </Button>
        </div>
      ) : null}
      {onDisarm && queue.armed ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          <div>
            <Button variant="quiet" onClick={onDisarm}>
              Turn the work line off
            </Button>
          </div>
          {queue.running !== null ? <span style={small}>The run in work finishes; nothing starts after it until the line is armed again.</span> : null}
        </div>
      ) : null}
      {live.length === 0 ? <p style={muted}>Nothing open.</p> : null}
      <ol aria-label="Work items" style={{ margin: 0, paddingLeft: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
        {live.map((item, i) => (
          <Item key={item.number} item={item} items={queue.items} first={i === 0} onUp={onOrder ? () => up(item.number) : undefined} onMove={onMove} />
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

// The work line is a brake, never an ignition (sunna#35): she arms it for
// a batch, its cap (when you set one) the only thing that stops a run,
// and it goes off when the queue clears.
function loopLine(name: string, q: Queue): string {
  const cap = q.budget ? `$${(q.budget.left / 1e9).toFixed(2)} left of $${(q.budget.cap / 1e9).toFixed(2)} a ${q.budget.period}` : 'no cap';
  const open = q.items.some((i) => i.status === 'open' || i.status === 'in_work');
  const by = q.armed_by === 'witness' ? ' by you' : q.armed_by === 'resident' ? ` by ${name}` : '';
  const budget = q.armed ? `Work line: armed${by}, ${cap}.` : open ? `Work line: off, waiting for ${name} to arm it.` : 'Work line: off, the queue is clear.';
  const runs = `${q.runs_today} of ${q.runs_a_day} runs today.`;
  // The loop steps over blocked items to the next open one (sunna#42).
  const blocked = q.items.filter((i) => i.status === 'blocked').map((i) => `#${i.number}`);
  const skips = blocked.length > 0 ? ` Stepping over blocked ${blocked.join(', ')}.` : '';
  if (q.running !== null) return `Running item #${q.running} now.${skips} ${runs} ${budget}`;
  if (q.rested) return `Resting: ${q.rested}. ${runs} ${budget}`;
  return `${name}'s loop has not run yet. ${budget}`;
}

// What blocks an item is another item of the queue (sunna#42): "#12"
// read as that item; anything else is a line from before the rule.
function blockedLine(on: string | null, items: WorkItem[]): string {
  const n = on && /^#\d+$/.test(on) ? Number(on.slice(1)) : null;
  if (n === null) return `blocked on ${on ?? 'something unnamed'}`;
  const other = items.find((i) => i.number === n);
  return other ? `blocked on #${n}: ${other.what}` : `blocked on #${n}`;
}

function Item({ item, items, first, onUp, onMove }: { item: WorkItem; items: WorkItem[]; first: boolean; onUp?: () => void; onMove?: WorkQueueProps['onMove'] }) {
  const [note, setNote] = useState('');
  const [blockedOn, setBlockedOn] = useState('');
  // What it can wait on: another item still to be done.
  const blockers = items.filter((i) => i.number !== item.number && i.status !== 'done' && i.status !== 'dropped');
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
        {item.status === 'blocked' ? blockedLine(item.blocked_on, items) : item.status === 'in_work' ? 'running now' : 'open'} · added by {item.added_by === 'witness' ? 'you' : 'her'} · {item.runs} runs
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
          {blockers.length > 0 ? (
            <>
              <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13, minWidth: 0 }}>
                Blocked on
                <select aria-label={`#${item.number} blocked on`} value={blockedOn} onChange={(e) => setBlockedOn(e.target.value)} style={{ minHeight: 'var(--control-h)', fontSize: 15, maxWidth: '100%' }}>
                  <option value="">another item…</option>
                  {blockers.map((b) => (
                    <option key={b.number} value={String(b.number)}>
                      #{b.number} {b.what}
                    </option>
                  ))}
                </select>
              </label>
              <Button variant="quiet" disabled={note.trim() === '' || blockedOn === ''} onClick={() => move('blocked')}>
                Blocked
              </Button>
            </>
          ) : null}
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
