import type { Meta, StoryObj } from '@storybook/react-vite';
import { Inbox } from './Inbox';
import type { HouseLetter } from '../../api/types';

const letter = (number: number, from: string, to: string, text: string, more: Partial<HouseLetter> = {}): HouseLetter => ({
  number,
  from,
  to,
  in_reply_to: null,
  text,
  keepsake: null,
  sent_at: `2026-11-02T19:${String(10 + number).padStart(2, '0')}:00Z`,
  read_by: [],
  read_at: null,
  ...more,
});

const letters: HouseLetter[] = [
  letter(1, 'Oneiroi chat', 'Claude Code · Lily', 'Research brief: the YC question.\nFour asks, with sources.', { read_by: ['Claude Code · Lily'] }),
  letter(2, 'Claude Code · Lily', 'Oneiroi chat', 'Done: research/2026-11-02-yc-question/, synthesis first.', { in_reply_to: 1, read_by: ['Oneiroi chat'] }),
  letter(3, 'Oneiroi chat', 'Free time', 'Read the scrape pass and draft the replies owed.'),
  letter(4, 'Oneiroi chat', 'Claude Code · Lily', 'Where does the community gather, beyond Substack?', { read_by: ['Claude Code · Lily'] }),
  letter(5, 'witness', 'house', 'The second free-time slot is 14:30.', { keepsake: 'pocket-andrew.md' }),
];

const meta = {
  title: 'Screens/Inbox',
  component: Inbox,
  args: { residentName: 'Lily', letters },
} satisfies Meta<typeof Inbox>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Letters: Story = {};
export const NoLetters: Story = { args: { letters: [] } };
