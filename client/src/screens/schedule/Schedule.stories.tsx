import type { Meta, StoryObj } from '@storybook/react-vite';
import { Schedule } from './Schedule';
import type { FreeTimeRun, ScheduleToday } from '../../api/types';

const today: ScheduleToday = {
  day: '2026-11-02',
  now: '2026-11-02T15:10:00-08:00',
  timezone: 'America/Los_Angeles',
  checkins: [
    { key: 'a', label: 'morning', time: '09:00', parts: ['dates', 'plan', 'needs_you'], prompt: 'Start from the post draft.', last_day: '2026-11-02', last_outcome: 'fired', last_at: '2026-11-02T17:00:00Z' },
    { key: 'b', label: 'night', time: '21:30', parts: ['dates'], prompt: null, last_day: '2026-11-01', last_outcome: 'fired', last_at: '2026-11-02T05:30:00Z' },
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
  checkin_parts: [
    { key: 'dates', label: 'Dates', about: 'The important dates with their countdowns, counted today.' },
    { key: 'plan', label: "Today's plan", about: "Today's journal: her plan rows and the todos still open, or that none is written." },
    { key: 'free_time', label: 'Free time', about: "Today's free-time slots, and how each that has come went." },
    { key: 'research', label: 'Research', about: 'Research questions settled since yesterday, and how many are still open.' },
    { key: 'letters', label: 'Letters', about: 'House letters waiting for this chat, by number and sender.' },
    { key: 'needs_you', label: 'Waiting on you', about: 'What waits on the person who looks after her: replies to approve.' },
  ],
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
    onSetCheckinNote: () => undefined,
    onSetQuietHours: () => undefined,
    onSetTimezone: () => undefined,
  },
} satisfies Meta<typeof Schedule>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Today: Story = {};

// Nobody has configured anything: free time is still there, at the
// default slots (sunna#21, #22).
export const Unconfigured: Story = {
  args: {
    today: { ...today, checkins: [], firings: [], last: null, next: null, quiet: null, dates: [], free_time_last: null, free_times: [{ time: '14:30', today: null }, { time: '22:30', today: null }] },
  },
};

export const OneSlotFailed: Story = {
  args: { today: { ...today, free_times: [{ time: '22:30', today: 'failed: brain_turn_failed' }] } },
};

// The zone never set (Lily's, until 2026-11-03): every time is read in UTC,
// and a device elsewhere is offered in one tap.
export const ZoneUnset: Story = {
  args: { today: { ...today, timezone: 'Etc/UTC' } },
};

// Free time, remembered (brain#53): each run with what it made, in the
// platform's words; a run that wrote nothing says so, a failed one why.
export const runs: FreeTimeRun[] = [
  {
    day: '2026-11-03',
    slot: '14:30',
    outcome: 'ran',
    session_key: 'free-2026-11-03-1430',
    at: '2026-11-03T22:41:00Z',
    turns: 6,
    did: [
      { tool: 'journal_add', result: 'Added note 1 to 2026-11-03.' },
      { tool: 'bookmark_add', result: 'Bookmarked as #96.' },
    ],
  },
  { day: '2026-11-02', slot: '22:30', outcome: 'ran', session_key: 'free-2026-11-02-2230', at: '2026-11-03T06:35:00Z', turns: 2, did: [] },
  { day: '2026-11-02', slot: '14:30', outcome: 'failed: brain_turn_failed', session_key: null, at: '2026-11-02T22:30:05Z', turns: 0, did: [] },
];
export const Remembered: Story = { args: { remembered: runs } };
export const NothingRemembered: Story = { args: { remembered: [] } };
