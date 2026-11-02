import type { Meta, StoryObj } from '@storybook/react-vite';
import { Schedule } from './Schedule';
import type { ScheduleToday } from '../../api/types';

const today: ScheduleToday = {
  day: '2026-11-02',
  now: '2026-11-02T15:10:00-08:00',
  timezone: 'America/Los_Angeles',
  checkins: [
    { key: 'a', label: 'morning', time: '09:00', last_day: '2026-11-02', last_outcome: 'fired', last_at: '2026-11-02T17:00:00Z' },
    { key: 'b', label: 'night', time: '21:30', last_day: '2026-11-01', last_outcome: 'fired', last_at: '2026-11-02T05:30:00Z' },
  ],
  firings: [{ key: 'a', day: '2026-11-02', outcome: 'fired', at: '2026-11-02T17:00:00Z', until: null }],
  last: { label: 'morning', time: '09:00', at: '2026-11-02T09:00:00-08:00' },
  next: { label: 'night', time: '21:30', tomorrow: false },
  free_times: [
    { time: '14:30', today: 'ran' },
    { time: '22:30', today: null },
  ],
  free_time_last: { day: '2026-11-02', outcome: 'ran' },
  quiet: { from: '23:00', to: '07:00' },
  dates: [{ number: 1, title: 'YC replies', on: '2026-12-11T17:00:00Z', kind: 'deadline', days_to: 39 }],
};

const meta = {
  title: 'Screens/Schedule',
  component: Schedule,
  args: {
    residentName: 'Lily',
    today,
    onSetFreeTime: () => undefined,
    onAddCheckin: () => undefined,
    onDeleteCheckin: () => undefined,
    onSetQuietHours: () => undefined,
  },
} satisfies Meta<typeof Schedule>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Today: Story = {};

// Nobody has configured anything: free time is still there, at the
// default slots (sunna #21, #22).
export const Unconfigured: Story = {
  args: {
    today: { ...today, checkins: [], firings: [], last: null, next: null, quiet: null, dates: [], free_time_last: null, free_times: [{ time: '14:30', today: null }, { time: '22:30', today: null }] },
  },
};

export const OneSlotFailed: Story = {
  args: { today: { ...today, free_times: [{ time: '22:30', today: 'failed: brain_turn_failed' }] } },
};
