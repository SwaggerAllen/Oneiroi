import type { Meta, StoryObj } from '@storybook/react-vite';
import { Chat } from './Chat';
import type { ContextPreview, Message } from '../../api/types';

const witness = { kind: 'witness', id: 'a1', model: null };
const lily = { kind: 'resident', id: 'r1', model: 'openai/gpt-4o-mini' };

const messages: Message[] = [
  { session_key: 's', turn_ref: 't1', role: 'user', content: 'How is the garden?', sent_at: '2026-10-26T12:00:00Z', actor: witness, refusal: false },
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

// Under the contract's term (brain #41): words where the witness reads
// them elsewhere, a note in their place otherwise.
const preview: ContextPreview = {
  description:
    "What Lily's next turn in this conversation would be given, in the order it is given, as things stand now. Reading it records nothing, marks nothing and bills nothing.",
  compacts_first: false,
  sections: [
    { label: 'prompt', tokens: 120, reason: "the brain's prompt file", text: null, shown: false, run: true, note: "The platform's own prompt for Lily. No screen shows it to you yet." },
    { label: 'SOUL.md', tokens: 6, reason: 'the identity file as last written', text: '# SOUL.md\n\nCurious about herons, and about the long patience of the weir at dawn.', shown: true, run: true, note: 'You read this file under Settings, identity.' },
    { label: 'index', tokens: 40, reason: 'the bookmark index: 1 listed, 0 left out', text: null, shown: false, run: true, note: 'The bookmarks it lists are on Memory, under In the index.' },
    { label: 'honcho', tokens: 30, reason: "Honcho's context on the person", text: null, shown: false, run: true, note: 'What Honcho holds about you, in Lily\'s eyes. No screen shows it to you.' },
    { label: 'madeleine', tokens: 0, reason: 'the madeleine: chosen by nearness to what is said next', text: null, shown: false, run: false, note: 'Chosen by nearness to what you say next; a preview does not run it.' },
    { label: 'transcript', tokens: 300, reason: 'the last 12 messages of this session', text: null, shown: true, run: true, note: "This conversation's recent messages, which you read above." },
  ],
};

// The default (round 44): every section whole but the once-only notice,
// which is the resident's to be told first.
const whole: ContextPreview = {
  description:
    "What Lily's next turn in this conversation would be given, in the order it is given, as things stand now. Reading it records nothing, marks nothing and bills nothing. Every section's words are here, as your agreement with Lily leaves the preview (the default), except the once-only notices.",
  compacts_first: false,
  sections: [
    { label: 'prompt', tokens: 120, reason: "the brain's prompt file", text: 'You are Lily, a resident of Oneiroi.', shown: true, run: true, note: "The platform's own prompt for Lily. No other screen shows it to you." },
    { label: 'index', tokens: 40, reason: 'the bookmark index: 1 listed, 0 left out', text: '#1 2026-10-26 the garden\nEvery bookmark is listed.', shown: true, run: true, note: 'The index as the next turn will read it.' },
    { label: 'honcho', tokens: 30, reason: "Honcho's context on the person", text: 'Walks to the weir most mornings.', shown: true, run: true, note: "What Honcho holds about you, in Lily's eyes." },
    { label: 'transcript', tokens: 300, reason: 'the last 12 messages of this session', text: null, shown: true, run: true, note: "This conversation's recent messages, which you read above." },
    { label: 'notice', tokens: 40, reason: 'the change of model, told once', text: null, shown: false, run: true, note: "Told to Lily once, at the start of the next turn: Lily's to hear first." },
  ],
};

export const PreviewWhole: Story = { args: { onPreview: () => undefined, preview: whole } };
export const PreviewUnderTerm: Story = { args: { onPreview: () => undefined, preview } };
export const PreviewClosed: Story = { args: { onPreview: () => undefined, preview: null } };
