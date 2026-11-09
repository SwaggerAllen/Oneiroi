import type { Meta, StoryObj } from '@storybook/react-vite';
import { WorkQueue } from './WorkQueue';

const meta: Meta<typeof WorkQueue> = { title: 'Screens/Schedule/WorkQueue', component: WorkQueue };
export default meta;
type Story = StoryObj<typeof WorkQueue>;

const base = {
  done_when: 'a draft for his read',
  blocked_on: null,
  added_at: '2026-11-06T22:00:00Z',
  note: null,
  moved_by: null,
  moved_at: null,
  shipped: null,
  slipped: null,
  why: null,
  wrapped_at: null,
  session_key: null,
};

export const Running: Story = {
  args: {
    residentName: 'Lily',
    queue: {
      items: [
        { ...base, number: 1, what: 'Generator brief', status: 'in_work', position: 1, added_by: 'resident', runs: 1 },
        { ...base, number: 2, what: 'E2E creation handoff test', status: 'open', position: 2, added_by: 'witness', runs: 0 },
        { ...base, number: 3, what: 'Drake letter', status: 'blocked', blocked_on: '#2', position: 3, added_by: 'resident', runs: 0 },
      ],
      running: 1,
      running_since: '2026-11-06T22:00:00Z',
      rested: null,
      rested_at: null,
      runs_today: 1,
      runs_a_day: 8,
      budget: { cap: 5e9, spent: 1e9, left: 4e9, period: 'day' },
      armed: true,
    },
  },
};

export const EmptyHolding: Story = {
  args: {
    residentName: 'Lily',
    queue: { items: [], running: null, running_since: null, rested: 'empty, holding', rested_at: '2026-11-06T22:00:00Z', runs_today: 0, runs_a_day: 8, budget: null, armed: false },
  },
};
