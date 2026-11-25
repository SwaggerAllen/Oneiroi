import type { BacklogArranged, BacklogEntry } from '../../api/types';

/**
 * The backlog's arrangement, edited in place (sunna#103): pure moves over
 * the entries, each answering the new list. Every change is sent whole
 * (`toArranged`), and the server keeps the top open whatever it says.
 */
export type Entries = BacklogEntry[];

export const where = (entries: Entries, n: number): number => entries.findIndex((e) => (e.kind === 'task' ? e.number === n : e.tasks.includes(n)));

/** Task `n` taken out wherever it is; a batch keeps its place even when it empties. */
export function without(entries: Entries, n: number): Entries {
  return entries.flatMap((e): Entries => {
    if (e.kind === 'task') return e.number === n ? [] : [e];
    return [{ ...e, tasks: e.tasks.filter((t) => t !== n) }];
  });
}

export type Move = 'top' | 'up' | 'down' | 'bottom';

const to = (how: Move, i: number, length: number) => ({ top: 0, up: Math.max(0, i - 1), down: Math.min(length, i + 1), bottom: length })[how];

/** A task moved within its batch, or, in no batch, among the entries. */
export function moveTask(entries: Entries, n: number, how: Move): Entries {
  const i = where(entries, n);
  if (i < 0) return entries;
  const e = entries[i];
  if (e.kind === 'batch') {
    const tasks = e.tasks.filter((t) => t !== n);
    tasks.splice(to(how, e.tasks.indexOf(n), tasks.length), 0, n);
    return entries.map((x, k) => (k === i ? { ...e, tasks } : x));
  }
  return moveEntry(entries, i, how);
}

/** A whole entry (a batch, or a task in no batch) moved among the entries. */
export function moveEntry(entries: Entries, i: number, how: Move): Entries {
  const rest = entries.filter((_, k) => k !== i);
  rest.splice(to(how, i, rest.length), 0, entries[i]);
  return rest;
}

/** Task `n` into batch `batch` (at its end), or, with null, out to the bottom in no batch, closed. */
export function toBatch(entries: Entries, n: number, batch: number | null): Entries {
  const rest = without(entries, n);
  if (batch === null) return [...rest, { kind: 'task', number: n, open: false, top: false }];
  return rest.map((e) => (e.kind === 'batch' && e.number === batch ? { ...e, tasks: [...e.tasks, n] } : e));
}

/** A dragged task dropped on another: it joins the target's batch before it, or stands alone before it. */
export function dropBefore(entries: Entries, n: number, target: number): Entries {
  if (n === target) return entries;
  const rest = without(entries, n);
  const i = where(rest, target);
  if (i < 0) return entries;
  const e = rest[i];
  if (e.kind === 'batch') return rest.map((x, k) => (k === i && x.kind === 'batch' ? { ...x, tasks: x.tasks.flatMap((t) => (t === target ? [n, t] : [t])) } : x));
  return [...rest.slice(0, i), { kind: 'task', number: n, open: false, top: false }, ...rest.slice(i)];
}

/** An entry opened or closed. */
export const flip = (entries: Entries, i: number): Entries => entries.map((e, k) => (k === i ? { ...e, open: !e.open } : e));

/** What the arrangement sends: empty batches dropped (the server lists a batch only while it holds open tasks). */
export function toArranged(entries: Entries): BacklogArranged[] {
  return entries.flatMap((e): BacklogArranged[] => {
    if (e.kind === 'task') return [{ task: e.number, open: e.open }];
    return e.tasks.length === 0 ? [] : [{ batch: e.number, tasks: e.tasks, open: e.open }];
  });
}
