import type { Meta, StoryObj } from '@storybook/react-vite';
import type { CorrespondenceMessage, Reply } from '../../api/types';
import { CorrespondencePage } from './CorrespondencePage';

const message = (number: number, sender: string, name: string, at: string, more: Partial<CorrespondenceMessage> = {}): CorrespondenceMessage => ({
  number,
  platform: 'email',
  account: 'strutlily@gmail.com',
  external_id: `x${number}`,
  sender,
  sender_name: name,
  verified: true,
  thread: null,
  subject: null,
  text: `Message ${number} from ${name}.`,
  sent_at: at,
  received_at: at,
  state: 'received',
  read_at: null,
  ...more,
});

const reply = (number: number, inReplyTo: number, to: string, at: string): Reply => ({
  number,
  in_reply_to: inReplyTo,
  platform: 'email',
  account: 'strutlily@gmail.com',
  thread: null,
  to,
  text: `Lily's reply #${number}.`,
  state: 'sent',
  note: null,
  drafted_at: at,
  decided_at: at,
  sent_at: at,
  sent_by: 'witness',
  url: null,
});

// The founding case (2026-11-07): a thread with Jack, hers and his mixed.
export const messages: CorrespondenceMessage[] = [
  message(1, 'jack@example.com', 'Jack', '2026-11-05T10:00:00Z', { subject: 'Your piece' }),
  message(2, 'grace@example.com', 'Grace', '2026-11-05T12:00:00Z', { subject: 'The directory' }),
  message(3, 'jack@example.com', 'Jack', '2026-11-07T09:00:00Z', { subject: 'Your piece' }),
];
export const replies: Reply[] = [reply(1, 1, 'jack@example.com', '2026-11-06T09:00:00Z')];

const meta = {
  title: 'Screens/Correspondence',
  component: CorrespondencePage,
  args: { residentName: 'Lily', messages, replies },
} satisfies Meta<typeof CorrespondencePage>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Everyone: Story = {};
export const NoneYet: Story = { args: { messages: [], replies: [] } };
