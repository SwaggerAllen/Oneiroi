import { describe, expect, it } from 'vitest';
import { dropBefore, flip, moveTask, toArranged, toBatch, type Entries } from './backlogMoves';

const start: Entries = [
  { kind: 'batch', number: 1, name: null, open: true, top: true, tasks: [12, 9] },
  { kind: 'task', number: 16, open: false, top: false },
  { kind: 'batch', number: 2, name: 'Social', open: false, top: false, tasks: [15, 17] },
  { kind: 'task', number: 14, open: false, top: false },
];

describe('the backlog arrangement (sunna#103)', () => {
  it('moves a task within its batch, and a loose task among the entries', () => {
    expect(toArranged(moveTask(start, 9, 'top'))[0]).toEqual({ batch: 1, tasks: [9, 12], open: true });
    expect(toArranged(moveTask(start, 14, 'top')).map((e) => ('task' in e ? e.task : e.batch))).toEqual([14, 1, 16, 2]);
  });

  it('moves a task into a batch, or out to the bottom in no batch', () => {
    expect(toArranged(toBatch(start, 16, 2))).toEqual([
      { batch: 1, tasks: [12, 9], open: true },
      { batch: 2, tasks: [15, 17, 16], open: false },
      { task: 14, open: false },
    ]);
    expect(toArranged(toBatch(start, 12, null)).slice(-1)).toEqual([{ task: 12, open: false }]);
  });

  it('drops a dragged task before another: into its batch, or standing alone', () => {
    expect(toArranged(dropBefore(start, 14, 17))[2]).toEqual({ batch: 2, tasks: [15, 14, 17], open: false });
    expect(toArranged(dropBefore(start, 9, 16)).slice(0, 3)).toEqual([{ batch: 1, tasks: [12], open: true }, { task: 9, open: false }, { task: 16, open: false }]);
  });

  it('opens and closes an entry, and sends no empty batch', () => {
    expect(toArranged(flip(start, 1))[1]).toEqual({ task: 16, open: true });
    const emptied = toBatch(toBatch(start, 15, null), 17, null);
    expect(toArranged(emptied).some((e) => 'batch' in e && e.batch === 2)).toBe(false);
  });
});
