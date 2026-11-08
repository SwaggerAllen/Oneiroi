import type { Meta, StoryObj } from '@storybook/react-vite';
import { Inbox } from './Inbox';
import type { Block, CorrespondenceMessage, HouseLetter, NeedsYouEntry, Reply } from '../../api/types';

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

export const Writing: Story = { args: { addresses: ['house', 'Free time', 'Oneiroi chat', 'Claude Code · Lily'], onSendLetter: () => undefined } };

const message = (number: number, sender: string, more: Partial<CorrespondenceMessage> = {}): CorrespondenceMessage => ({
  number,
  platform: 'email',
  account: 'strutlily@gmail.com',
  external_id: `x${number}`,
  sender,
  sender_name: 'Grace',
  verified: true,
  thread: null,
  subject: 'The directory',
  text: 'Hello Lily,\nI added you to the directory.',
  sent_at: '2026-11-02T18:00:00Z',
  received_at: '2026-11-02T20:30:00Z',
  state: 'received',
  read_at: null,
  ...more,
});

const reply = (number: number, state: Reply['state'], text: string, more: Partial<Reply> = {}): Reply => ({
  number,
  in_reply_to: 3,
  platform: 'substack',
  account: 'lily',
  thread: null,
  to: 'max',
  text,
  state,
  note: null,
  drafted_at: '2026-11-02T21:00:00Z',
  decided_at: null,
  sent_at: null,
  sent_by: null,
  url: null,
  ...more,
});

const blocks: Block[] = [
  { platform: 'substack', identity: 'troll', name: 'Troll', note: 'Harassment.', blocked_by: 'witness', blocked_at: '2026-11-02T20:00:00Z' },
  { platform: 'email', identity: 'spam@example.com', name: null, note: 'Spam.', blocked_by: 'resident', blocked_at: '2026-11-02T20:05:00Z' },
];

const needsYou: NeedsYouEntry[] = [
  { kind: 'ask', ref: 4, since: '2026-11-01T12:00:00Z', screen: 'inbox', long: false, about: { subject: 'Post the essay on Notes', ask: 'act' } },
  { kind: 'reply_to_approve', ref: 1, since: '2026-11-02T21:00:00Z', screen: 'inbox', long: false, about: { to: 'max', platform: 'substack', account: 'lily' } },
  { kind: 'reply_to_send', ref: 2, since: '2026-11-02T21:30:00Z', screen: 'inbox', long: false, about: { to: 'max', platform: 'substack', account: 'lily' } },
  { kind: 'work_blocked', ref: 7, since: '2026-11-02T22:00:00Z', screen: 'work', long: false, about: { what: 'Re-stage the Jack letter', blocked_on: 'the address to draft from' } },
];

export const Gate: Story = {
  args: {
    now: Date.parse('2026-11-03T00:00:00Z'),
    needsYou,
    messages: [
      message(4, 'max', { platform: 'substack', sender_name: 'Max', thread: 'essay', text: 'And another thing.', sent_at: '2026-11-02T22:00:00Z' }),
      message(3, 'max', { platform: 'substack', sender_name: 'Max', thread: 'essay', read_at: '2026-11-02T21:00:00Z' }),
      message(2, 'troll', { platform: 'substack', sender_name: null, subject: null, text: null, state: 'blocked' }),
      message(1, 'grace@example.com', { verified: false }),
    ],
    replies: [
      reply(1, 'drafted', 'Dear Max, thank you.'),
      reply(2, 'approved', 'An approved one.', { decided_at: '2026-11-02T21:30:00Z' }),
      reply(3, 'sent', 'Sent already.', { sent_at: '2026-11-02T21:10:00Z' }),
      reply(5, 'superseded', 'An older go.', { superseded_by: 1 }),
    ],
    blocks,
    actions: { onDecideReply: () => undefined, onMarkSent: () => undefined, onBlock: () => undefined, onUnblock: () => undefined },
  },
};
