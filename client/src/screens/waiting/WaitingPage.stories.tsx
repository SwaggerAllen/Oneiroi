import type { Meta, StoryObj } from '@storybook/react-vite';
import type { NeedsYouEntry } from '../../api/types';
import { WaitingPage } from './WaitingPage';

// The approval queue: three waiting, one past a day (the Jack draft's case).
export const entries: NeedsYouEntry[] = [
  { kind: 'reply_to_approve', ref: 4, since: '2026-11-05T17:00:00Z', screen: 'inbox', long: true, about: { to: 'jack@example.com', platform: 'email', account: 'lily' } },
  { kind: 'ask', ref: 2, since: '2026-11-08T15:00:00Z', screen: 'inbox', long: false, about: { subject: 'Post the essay on Notes', ask: 'act' } },
  { kind: 'work_blocked', ref: 7, since: '2026-11-08T16:00:00Z', screen: 'work', long: false, about: { what: 'Re-stage the Jack letter', blocked_on: 'the address' } },
];

const meta = {
  title: 'Screens/Waiting',
  component: WaitingPage,
  args: { residentName: 'Lily', entries, rule: 'all', onRule: () => undefined, onOpen: () => undefined, now: Date.parse('2026-11-08T18:00:00Z') },
} satisfies Meta<typeof WaitingPage>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Waiting: Story = {};
export const Nothing: Story = { args: { entries: [] } };
