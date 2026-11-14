import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type OperatorItem } from '../../api/client';
import { Linked } from '../shell/Linked';
import { SaidLine } from './parts';
import { useOp } from './useOp';
import * as css from './operator.css';

const BY: Record<string, string> = { agent: 'the agent', operator: 'you', platform: 'the platform' };

/**
 * The operator's queue (apsu#31; the witness, 2026-11-13: "stuff falling
 * off my radar is pretty common"): what waits on whoever runs the
 * platform, raised by the agent with its ops token, by the platform or by
 * you, closed done or dropped with a note.
 */
export function Queue() {
  const queue = useQuery({ queryKey: ['operator', 'queue'], queryFn: api.operatorQueue });
  const op = useOp();
  const [what, setWhat] = useState('');
  const [why, setWhy] = useState('');
  const open = queue.data?.open ?? [];
  return (
    <>
      <section className={css.card} aria-label="Waiting on the operator">
        <h2 className={css.heading}>WAITING ON YOU · {open.length}</h2>
        {queue.isPending && <p className={css.note}>Reading…</p>}
        {queue.data && open.length === 0 && <p className={css.note}>Nothing waits on you.</p>}
        {open.map((i) => (
          <Item key={i.number} item={i} />
        ))}
      </section>
      <section className={css.card} aria-label="Add an item">
        <h2 className={css.heading}>ADD ONE</h2>
        <input className={css.input} placeholder="What is needed" value={what} onChange={(e) => setWhat(e.target.value)} aria-label="What" />
        <input className={css.input} placeholder="Why (optional)" value={why} onChange={(e) => setWhy(e.target.value)} aria-label="Why" />
        <div className={css.buttons}>
          <button
            type="button"
            className={css.primary}
            disabled={!what.trim() || op.busy}
            onClick={() =>
              void op
                .run(() => api.raiseOperatorItem(what.trim(), why.trim(), []).then((r) => `Added #${r.number}.`), ['operator', 'queue'])
                .then((ok) => {
                  if (ok) {
                    setWhat('');
                    setWhy('');
                  }
                })
            }
          >
            Add
          </button>
        </div>
        <SaidLine said={op.said} />
      </section>
      {(queue.data?.closed.length ?? 0) > 0 && (
        <section className={css.card} aria-label="Lately closed">
          <h2 className={css.heading}>LATELY CLOSED</h2>
          {(queue.data?.closed ?? []).map((i) => (
            <p key={i.number} className={css.note}>
              #{i.number} {i.what} · {i.status}
              {i.note ? ` — “${i.note}”` : ''}
            </p>
          ))}
        </section>
      )}
    </>
  );
}

function Item({ item }: { item: OperatorItem }) {
  const op = useOp();
  const [note, setNote] = useState('');
  const close = (status: 'done' | 'dropped') =>
    void op.run(() => api.closeOperatorItem(item.number, status, note.trim()).then(() => `#${item.number} is ${status}.`), ['operator', 'queue']);
  return (
    <div className={css.failure}>
      <span>
        <strong>#{item.number}</strong> <Linked text={item.what} />
      </span>
      {item.why && (
        <span className={css.note}>
          <Linked text={item.why} />
        </span>
      )}
      {item.links.map((l) => (
        <a key={l} className={css.mono} href={l} target="_blank" rel="noreferrer">
          {l}
        </a>
      ))}
      <span className={css.mono}>
        raised by {BY[item.raised_by] ?? item.raised_by} · {new Date(item.raised_at).toLocaleString()}
      </span>
      <div className={css.inline}>
        <input className={css.input} placeholder="A note (needed to close)" value={note} onChange={(e) => setNote(e.target.value)} aria-label={`Note on #${item.number}`} />
        <button type="button" className={css.primary} disabled={!note.trim() || op.busy} onClick={() => close('done')}>
          Done
        </button>
        <button type="button" className={css.button} disabled={!note.trim() || op.busy} onClick={() => close('dropped')}>
          Drop
        </button>
      </div>
      <SaidLine said={op.said} />
    </div>
  );
}
