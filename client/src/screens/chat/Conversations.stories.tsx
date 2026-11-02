import type { Meta, StoryObj } from '@storybook/react-vite';
import type { Session } from '../../api/types';
import { Conversations } from './Conversations';

const session = (key: string, title: string, place: string | null, writable: boolean, turns: number, at: string): Session => ({
  key,
  resident_id: 'r1',
  kind: writable ? 'main' : 'adapter',
  adapter: writable ? 'brain' : 'laptop',
  title,
  place,
  writable,
  turns,
  opened_at: at,
  last_turn_at: at,
  summary: null,
});

// As the server lists them: last spoken in first, each named.
export const sessions: Session[] = [
  session('c2', 'Claude Code · Oneiroi', 'Oneiroi', false, 7, '2026-11-02T14:03:00Z'),
  session('c3', 'Claude Code · catapult', 'catapult', false, 2, '2026-11-02T13:40:00Z'),
  session('chat', 'Oneiroi chat', null, true, 12, '2026-11-02T13:10:00Z'),
  session('c1', 'Claude Code · Oneiroi', 'Oneiroi', false, 1, '2026-11-01T09:00:00Z'),
];

const meta = {
  title: 'Screens/Chat/Conversations',
  component: Conversations,
  args: { sessions, chatKey: 'chat', current: 'chat', onOpen: () => undefined },
} satisfies Meta<typeof Conversations>;
export default meta;
type Story = StoryObj<typeof meta>;

// One variation per state (conventions §9).
export const ChatOpen: Story = {};
export const ClaudeCodeOpen: Story = { args: { current: 'c2' } };
export const OnlyTheChat: Story = { args: { sessions: [sessions[2]] } };
