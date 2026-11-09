import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { WorkItem, WorkQueue as Queue } from '../../api/types';
import { WorkQueue } from './WorkQueue';

const item = (n: number, over: Partial<WorkItem> = {}): WorkItem => ({
  number: n,
  what: `Item ${n}`,
  done_when: 'drafted',
  status: 'open',
  blocked_on: null,
  position: n,
  added_by: 'resident',
  added_at: '2026-11-06T22:00:00Z',
  note: null,
  moved_by: null,
  moved_at: null,
  shipped: null,
  slipped: null,
  why: null,
  wrapped_at: null,
  runs: 0,
  session_key: null,
  ...over,
});

const queue = (over: Partial<Queue> = {}): Queue => ({
  items: [item(1, { status: 'in_work', runs: 1 }), item(2, { added_by: 'witness' }), item(3, { status: 'done', shipped: 'the brief' })],
  running: 1,
  running_since: '2026-11-06T22:00:00Z',
  rested: null,
  rested_at: null,
  runs_today: 1,
  runs_a_day: 8,
  budget: { cap: 5e9, spent: 1e9, left: 4e9, period: 'day' },
  armed: true,
  ...over,
});

describe('WorkQueue', () => {
  it('shows the loop, the live items in order, and the finished apart', () => {
    render(<WorkQueue residentName="Lily" queue={queue()} />);
    expect(screen.getByText(/Running item #1 now\. 1 of 8 runs today\. Work line: armed, \$4\.00 left of \$5\.00 a day\./)).toBeTruthy();
    expect(screen.getByText('running now · added by her · 1 runs')).toBeTruthy();
    expect(screen.getByText('open · added by you · 0 runs')).toBeTruthy();
    expect(screen.getByText('#3 Item 3: done. Shipped: the brief')).toBeTruthy();
  });

  it('says why the loop rests, and that the line is off when the queue is clear', () => {
    render(<WorkQueue residentName="Lily" queue={queue({ items: [], running: null, rested: 'empty, holding', budget: null, armed: false })} />);
    expect(screen.getByText(/Resting: empty, holding\..*Work line: off, the queue is clear\./)).toBeTruthy();
  });

  it('off with work open says it waits for her to arm it', () => {
    render(<WorkQueue residentName="Lily" queue={queue({ running: null, armed: false })} />);
    expect(screen.getByText(/Work line: off, waiting for Lily to arm it\./)).toBeTruthy();
  });

  it('armed with no cap says so', () => {
    render(<WorkQueue residentName="Lily" queue={queue({ budget: null })} />);
    expect(screen.getByText(/Work line: armed, no cap\./)).toBeTruthy();
  });

  it('adds an item, moves one with a note, and moves one up', () => {
    const onAdd = vi.fn();
    const onMove = vi.fn();
    const onOrder = vi.fn();
    render(<WorkQueue residentName="Lily" queue={queue()} onAdd={onAdd} onMove={onMove} onOrder={onOrder} />);
    fireEvent.change(screen.getByLabelText('What (one line)'), { target: { value: 'E2E test' } });
    fireEvent.change(screen.getByLabelText('Done when'), { target: { value: 'green' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add to the queue' }));
    expect(onAdd).toHaveBeenCalledWith('E2E test', 'green');
    fireEvent.change(screen.getByLabelText('A note on #2'), { target: { value: 'not yet' } });
    fireEvent.click(screen.getAllByRole('button', { name: 'Done' })[1]);
    expect(onMove).toHaveBeenCalledWith(2, 'done', null, 'not yet');
    fireEvent.click(screen.getByRole('button', { name: 'Move up' }));
    expect(onOrder).toHaveBeenCalledWith([2, 1]);
  });

  // sunna#42: blocked is on another item, picked from the queue, and
  // says which.
  it('blocks an item on another one picked from the queue, and names it', () => {
    cleanup();
    const onMove = vi.fn();
    render(
      <WorkQueue
        residentName="Lily"
        queue={queue({ items: [item(1, { status: 'in_work' }), item(2), item(4, { status: 'blocked', blocked_on: '#2' }), item(3, { status: 'done' })] })}
        onMove={onMove}
      />,
    );
    expect(screen.getByText(/blocked on #2: Item 2/)).toBeTruthy();
    const picker = screen.getByRole('combobox', { name: '#2 blocked on' }) as HTMLSelectElement;
    // Not itself, not a done item.
    expect(Array.from(picker.options).map((o) => o.text)).toEqual(['another item…', '#1 Item 1', '#4 Item 4']);
    fireEvent.change(screen.getByLabelText('A note on #2'), { target: { value: 'after the doc' } });
    fireEvent.change(picker, { target: { value: '1' } });
    fireEvent.click(screen.getAllByRole('button', { name: 'Blocked' })[1]);
    expect(onMove).toHaveBeenCalledWith(2, 'blocked', '1', 'after the doc');
  });
});
