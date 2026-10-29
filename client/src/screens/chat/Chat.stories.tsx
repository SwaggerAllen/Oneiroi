import type { Meta, StoryObj } from '@storybook/react-vite';
import { Chat } from './Chat';
import type { Message } from '../../api/types';

const steward = { kind: 'steward', id: 'a1', model: null };
const lily = { kind: 'resident', id: 'r1', model: 'openai/gpt-4o-mini' };

const messages: Message[] = [
  { session_key: 's', turn_ref: 't1', role: 'user', content: 'How is the garden?', sent_at: '2026-10-26T12:00:00Z', actor: steward, refusal: false },
  { session_key: 's', turn_ref: 't1', role: 'tool', content: 'bookmark_add({"line":"the garden"}) -> Bookmarked as #1.', sent_at: '2026-10-26T12:00:01Z', actor: lily, refusal: false },
  { session_key: 's', turn_ref: 't1', role: 'assistant', content: 'The tomatoes want water. I bookmarked that you asked.', sent_at: '2026-10-26T12:00:02Z', actor: lily, refusal: false },
];

const meta = {
  title: 'Screens/Chat',
  component: Chat,
  args: { residentName: 'Lily', messages, onSend: () => undefined, onInspect: () => undefined, drewOn: { t1: 4 } },
} satisfies Meta<typeof Chat>;
export default meta;
type Story = StoryObj<typeof meta>;

// One variation per state (conventions §9).
export const Empty: Story = { args: { messages: [] } };
export const Conversation: Story = {};
export const Streaming: Story = {
  args: { streaming: { turnRef: 't2', text: 'Let me think about' } },
};
export const Refusal: Story = {
  args: {
    messages: [
      messages[0],
      { ...messages[2], content: 'I would rather not say.', refusal: true },
    ],
  },
};
export const BudgetStop: Story = {
  args: {
    messages: [
      messages[0],
      {
        session_key: 's',
        turn_ref: 't1',
        role: 'system',
        content: 'The budget line for chat is spent for this month. Lily will answer again when it opens.',
        sent_at: '2026-10-26T12:00:02Z',
        actor: { kind: 'platform', id: null, model: null },
        refusal: false,
      },
    ],
  },
};
export const DrewOnOpen: Story = {
  args: {
    injections: {
      t1: [
        { label: 'prompt', tokens: 120, reason: "the brain's prompt file with the resident's name", position: 0, text: null },
        { label: 'index', tokens: 40, reason: 'the bookmark index under 1500 tokens: 1 listed, 0 left out', position: 1, text: '#1 2026-10-26 the garden\nEvery bookmark is listed.' },
        { label: 'transcript', tokens: 300, reason: 'the last 12 messages of this session', position: 2, text: null },
      ],
    },
  },
};
