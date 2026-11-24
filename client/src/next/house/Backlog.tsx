import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { BacklogEntry, BacklogFinished, QueueCard, QueueOverview, QueueTask } from '../../api/types';
import { Field, Said } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { HOUSE } from './keys';
import { dropBefore, flip, moveEntry, moveTask, toArranged, toBatch, type Entries, type Move } from './backlogMoves';
import { actName, nameOf, type Names } from './queueText';
import * as w from './work.css';
import { useWorkNav, workPath } from './workRoutes';

const QUEUE = [...HOUSE, 'queue'];
const KEY = [...QUEUE, 'backlog'];

/**
 * The backlog (sunna#103; the witness, 2026-11-24, the queue mocks'
 * Backlog board): the house's work in priority order, each entry a
 * numbered batch or a task in no batch, open or closed, the top always
 * open. Lines work only what is open. A witness reorders by dragging a
 * row's handle (touch too) or from its ⋯ menu, moves a task between
 * batches, opens and closes entries and makes batches; a resident reads
 * it. What finished lists below, newest first.
 */
export function Backlog({ overview: q, names, cards }: { overview: QueueOverview; names: Names; cards: QueueCard[] }) {
  const queries = useQueryClient();
  const backlog = useQuery({ queryKey: KEY, queryFn: api.queueBacklog });
  const [entries, setEntries] = useState<Entries | null>(null);
  const witness = q.me.startsWith('witness:');
  const act = useAct();

  useEffect(() => {
    if (backlog.data) setEntries(backlog.data.entries);
  }, [backlog.data]);

  const send = useMutation({
    mutationFn: (next: Entries) => api.queueArrange(toArranged(next)),
    onSettled: () => void queries.invalidateQueries({ queryKey: QUEUE }),
  });

  const change = (next: Entries) => {
    setEntries(next);
    send.mutate(next);
  };

  if (backlog.isPending || !entries) return <p className={css.note}>Reading…</p>;
  if (backlog.isError) return <p className={css.note}>The backlog could not be read.</p>;

  const byNumber = new Map(q.tasks.map((t) => [t.number, t]));
  const batches = entries.filter((e): e is Extract<BacklogEntry, { kind: 'batch' }> => e.kind === 'batch');

  return (
    <div className={css.column}>
      <p className={css.note}>The house's work in priority order. Lines work only what is open; the top is always open.{witness ? ' Drag a row by its handle, or use its ⋯ menu.' : ''}</p>
      {witness && <NewBatch entries={entries} tasks={byNumber} onMade={change} act={act} />}
      <Said said={act.said} />
      {entries.length === 0 && <p className={css.note}>Nothing is open in the house queue.</p>}
      <Rows entries={entries} tasks={byNumber} batches={batches} cards={cards} names={names} witness={witness} onChange={change} />
      <Finished finished={backlog.data?.finished ?? []} tasks={byNumber} />
    </div>
  );
}

type Batch = Extract<BacklogEntry, { kind: 'batch' }>;

function Rows({
  entries,
  tasks,
  batches,
  cards,
  names,
  witness,
  onChange,
}: {
  entries: Entries;
  tasks: Map<number, QueueTask>;
  batches: Batch[];
  cards: QueueCard[];
  names: Names;
  witness: boolean;
  onChange: (next: Entries) => void;
}) {
  const [menu, setMenu] = useState<number | null>(null);
  const [drag, setDrag] = useState<{ n: number; over: number | null } | null>(null);
  const root = useRef<HTMLDivElement>(null);

  // The task under the pointer, read off the rows, for a drag that works by touch as well as mouse.
  const under = (x: number, y: number): number | null => {
    const el = document.elementFromPoint(x, y)?.closest('[data-task]');
    return el && root.current?.contains(el) ? Number(el.getAttribute('data-task')) : null;
  };

  const handle = (n: number) =>
    witness ? (
      <button
        type="button"
        className={w.handle}
        aria-label={`Drag task #${n}`}
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId);
          setDrag({ n, over: null });
        }}
        onPointerMove={(e) => drag && setDrag({ n: drag.n, over: under(e.clientX, e.clientY) })}
        onPointerUp={(e) => {
          const target = under(e.clientX, e.clientY);
          if (drag && target !== null && target !== drag.n) onChange(dropBefore(entries, drag.n, target));
          setDrag(null);
        }}
        onPointerCancel={() => setDrag(null)}
      >
        <svg width="14" height="18" viewBox="0 0 14 18" fill="currentColor" aria-hidden="true">
          <circle cx="4" cy="3" r="1.6" />
          <circle cx="10" cy="3" r="1.6" />
          <circle cx="4" cy="9" r="1.6" />
          <circle cx="10" cy="9" r="1.6" />
          <circle cx="4" cy="15" r="1.6" />
          <circle cx="10" cy="15" r="1.6" />
        </svg>
      </button>
    ) : null;

  const row = (n: number, rank: string, loose: { i: number; e: BacklogEntry } | null) => {
    const t = tasks.get(n);
    const now = cards.filter((c) => c.task === n && t && c.layer === t.open_layer && (c.view === 'ready' || c.view === 'active' || c.view === 'blocked'));
    const step = now[0];
    const status = step ? `${actName(step)} · ${nameOf(names, step.assignee)} · ${step.view}` : 'between steps';
    return (
      <div key={n} data-task={n} className={`${w.backlogRow} ${drag?.over === n ? w.backlogTarget : ''}`}>
        {handle(n)}
        <span className={w.backlogRank}>{rank}</span>
        <div className={css.column} style={{ flex: 1, minWidth: 0, gap: 4 }}>
          <TaskLink n={n} title={t?.title ?? `Task #${n}`} />
          <span className={w.meta}>
            #{n} · {t?.project ?? ''}
          </span>
          <span className={css.note}>{status}</span>
          {menu === n && witness && <Menu n={n} entries={entries} batches={batches} inBatch={loose === null} onChange={onChange} />}
        </div>
        <div className={css.column} style={{ alignItems: 'flex-end', gap: 6 }}>
          {loose && <OpenPill entry={loose.e} onFlip={witness ? () => onChange(flip(entries, loose.i)) : undefined} />}
          {witness && (
            <button type="button" className={w.handle} aria-label={`Move task #${n}`} aria-expanded={menu === n} onClick={() => setMenu(menu === n ? null : n)}>
              ⋯
            </button>
          )}
        </div>
      </div>
    );
  };

  return (
    <div ref={root} className={css.column} style={{ gap: 12 }}>
      {entries.map((e, i) => {
        const rank = String(i + 1);
        const closed = !(e.open || e.top);
        if (e.kind === 'task') {
          return (
            <div key={`t${e.number}`} className={closed ? w.backlogClosed : undefined}>
              {row(e.number, rank, { i, e })}
            </div>
          );
        }
        return (
          <section key={`b${e.number}`} aria-label={`Batch ${e.number}`} className={`${w.backlogBatch} ${closed ? w.backlogClosed : w.backlogOpen}`}>
            <div className={w.backlogHead}>
              <span>
                <span className={w.backlogRank}>{rank}</span> <strong>Batch {e.number}</strong>
                {e.name ? ` · ${e.name}` : ''}
              </span>
              <OpenPill entry={e} onFlip={witness ? () => onChange(flip(entries, i)) : undefined} />
            </div>
            {witness && (
              <div className={css.row}>
                <button type="button" className={css.secondary} onClick={() => onChange(moveEntry(entries, i, 'up'))}>
                  Batch up
                </button>
                <button type="button" className={css.secondary} onClick={() => onChange(moveEntry(entries, i, 'down'))}>
                  Batch down
                </button>
              </div>
            )}
            {e.tasks.map((n, j) => row(n, `${rank}.${j + 1}`, null))}
          </section>
        );
      })}
    </div>
  );
}

function TaskLink({ n, title }: { n: number; title: string }) {
  const nav = useWorkNav();
  return (
    <a
      href={`#${workPath.task(n)}`}
      onClick={(e) => {
        e.preventDefault();
        nav(workPath.task(n));
      }}
      style={{ fontWeight: 600, fontSize: 15, lineHeight: '20px' }}
    >
      {title}
    </a>
  );
}

function OpenPill({ entry, onFlip }: { entry: BacklogEntry; onFlip?: () => void }) {
  const word = entry.top ? 'Open · top' : entry.open ? 'Open' : 'Closed';
  return (
    <button type="button" className={w.pill} aria-pressed={entry.open || entry.top} disabled={entry.top || !onFlip} onClick={onFlip}>
      {word}
    </button>
  );
}

function Menu({ n, entries, batches, inBatch, onChange }: { n: number; entries: Entries; batches: Batch[]; inBatch: boolean; onChange: (next: Entries) => void }) {
  const moves: [Move, string][] = [
    ['top', 'Top'],
    ['up', 'Up'],
    ['down', 'Down'],
    ['bottom', 'Bottom'],
  ];
  const mine = batches.find((b) => b.tasks.includes(n))?.number ?? null;
  return (
    <div className={w.backlogMenu}>
      <div className={css.row}>
        {moves.map(([how, word]) => (
          <button key={how} type="button" className={css.secondary} onClick={() => onChange(moveTask(entries, n, how))}>
            {word}
          </button>
        ))}
      </div>
      <span className={css.note}>{inBatch ? 'Its batch' : 'Batch'}</span>
      <div className={w.segmented}>
        {batches.map((b) => (
          <button key={b.number} type="button" className={w.pill} aria-pressed={mine === b.number} onClick={() => onChange(toBatch(entries, n, b.number))}>
            Batch {b.number}
          </button>
        ))}
        <button type="button" className={w.pill} aria-pressed={mine === null} onClick={() => mine !== null && onChange(toBatch(entries, n, null))}>
          No batch
        </button>
      </div>
    </div>
  );
}

/** A new numbered batch: a name (optional), its tasks, where it goes, and whether it opens now. */
function NewBatch({ entries, tasks, onMade, act }: { entries: Entries; tasks: Map<number, QueueTask>; onMade: (next: Entries) => void; act: ReturnType<typeof useAct> }) {
  const [shown, setShown] = useState(false);
  const [name, setName] = useState('');
  const [picked, setPicked] = useState<number[]>([]);
  const [top, setTop] = useState(false);
  const [open, setOpen] = useState(false);
  const live = entries.flatMap((e) => (e.kind === 'task' ? [e.number] : e.tasks));

  if (!shown)
    return (
      <div>
        <button type="button" className={css.secondary} onClick={() => setShown(true)}>
          New batch
        </button>
      </div>
    );

  const make = () =>
    void act.run(async () => {
      const { number } = await api.queueMakeBatch(name.trim() || null);
      const rest = picked.reduce((acc, n) => toBatch(acc, n, null).filter((e) => !(e.kind === 'task' && e.number === n)), entries);
      const batch: BacklogEntry = { kind: 'batch', number, name: name.trim() || null, open, top: false, tasks: picked };
      onMade(top ? [batch, ...rest] : [...rest, batch]);
      setShown(false);
      setName('');
      setPicked([]);
      return `Batch ${number} made.`;
    });

  return (
    <div className={w.backlogBatch}>
      <Field label="Name (optional)" value={name} onChange={(e) => setName(e.target.value)} />
      <span className={css.note}>Its tasks</span>
      {live.map((n) => (
        <label key={n} className={css.check}>
          <input type="checkbox" checked={picked.includes(n)} onChange={(e) => setPicked(e.target.checked ? [...picked, n] : picked.filter((x) => x !== n))} />#{n} {tasks.get(n)?.title ?? ''}
        </label>
      ))}
      <label className={css.check}>
        <input type="checkbox" checked={top} onChange={(e) => setTop(e.target.checked)} />
        At the top (else at the bottom)
      </label>
      <label className={css.check}>
        <input type="checkbox" checked={open} onChange={(e) => setOpen(e.target.checked)} />
        Open it now
      </label>
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy || picked.length === 0} onClick={make}>
          Make the batch
        </button>
        <button type="button" className={css.secondary} onClick={() => setShown(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}

function Finished({ finished, tasks }: { finished: BacklogFinished[]; tasks: Map<number, QueueTask> }) {
  if (finished.length === 0) return null;
  return (
    <section aria-label="Finished" className={css.column} style={{ gap: 8, paddingTop: 12 }}>
      <h2 className={w.section}>Finished · newest first</h2>
      {finished.slice(0, 30).map((f) => (
        <div key={`${f.kind}${f.number}`} className={w.finishedRow}>
          <span className={w.finishedWhen}>{new Date(f.at).toLocaleString([], { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' })}</span>
          <span>
            {f.kind === 'batch'
              ? `Batch ${f.number}${f.name ? ` · ${f.name}` : ''}, all its tasks`
              : `#${f.number} ${tasks.get(f.number)?.title ?? ''}${f.status === 'dropped' ? ' (dropped)' : ''}${f.batch ? ` · in Batch ${f.batch}` : ''}`}
          </span>
        </div>
      ))}
    </section>
  );
}
