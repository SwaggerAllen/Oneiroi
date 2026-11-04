import type { Meta, StoryObj } from '@storybook/react-vite';
import { Chat } from './Chat';
import type { ContextPreview, Message } from '../../api/types';
import { sessions } from './Conversations.stories';

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
  parameters: { layout: 'fullscreen' },
  // The space the shell gives Chat: the screen's height, less nothing
  // here, so the transcript scrolls inside it as it does in the app.
  decorators: [
    (Story) => (
      <div style={{ height: '100dvh', display: 'flex', flexDirection: 'column' }}>
        <Story />
      </div>
    ),
  ],
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

// Under the contract's term (brain#41): words where the witness reads
// them elsewhere, a note in their place otherwise.
const preview: ContextPreview = {
  description:
    "What Lily's next turn in this conversation would be given, in the order it is given, as things stand now. Reading it records nothing, marks nothing and bills nothing.",
  compacts_first: false,
  sections: [
    { label: 'prompt', tokens: 120, reason: "the brain's prompt file", text: null, shown: false, run: true, note: "The platform's own prompt for Lily. No screen shows it to you yet." },
    { label: 'SOUL.md', tokens: 6, reason: 'the identity file as last written', text: '# SOUL.md\n\nCurious about herons, and about the long patience of the weir at dawn.', shown: true, run: true, note: 'You read this file under Settings, identity.' },
    { label: 'index', tokens: 40, reason: 'the bookmark index: 1 listed, 0 left out', text: null, shown: false, run: true, note: 'Ranked against each turn\'s words; what it returned is in that reply\'s "drew on" list.' },
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

// The resident's stress test for the overflow: a wall of text with a word
// longer than the screen, and a tool call that runs for screens.
const longCall = `library_read({"path":"design/oneiroi-spec.md"}) -> ${'§6.5 the library holds every kind of document. '.repeat(60)}\n${'{"kind":"writing","path":"writing/the-bake-off.md","hash":"' + 'a'.repeat(400) + '"}\n'.repeat(12)}`;
export const LongToolCall: Story = {
  args: {
    messages: [
      messages[0],
      { ...messages[1], content: longCall },
      { ...messages[2], content: `A wall of my own: ${'https://example.com/' + 'x'.repeat(300)} and then ${'the words go on, '.repeat(80)}` },
    ],
  },
};

// Paged in from the newest: earlier messages remain, and a marker where
// the last visit left off (cursors are `sequence:position`).
const paged: Message[] = Array.from({ length: 12 }, (_, i) => ({
  ...messages[i % 2 === 0 ? 0 : 2],
  cursor: `${i + 1}:0`,
  turn_ref: `t${i + 1}`,
  content: i % 2 === 0 ? `Question ${i / 2 + 1}` : `Answer ${(i + 1) / 2}`,
}));
export const Unread: Story = { args: { messages: paged, more: true, onOlder: () => undefined, lastRead: '6:0', onRead: () => undefined } };

// A Claude Code conversation (kumbukumbu#40): read here, answered
// there, with its replies' inspector and no composer or preview.
export const ReadOnly: Story = {
  args: {
    conversation: { title: 'Claude Code · Oneiroi', writable: false },
    onPreview: () => undefined,
    injections: {
      t1: [
        { label: 'where', tokens: 60, reason: 'where this conversation is (kumbukumbu#42)', position: 0, text: 'This conversation is in Claude Code, in the folder Oneiroi.' },
        { label: 'index', tokens: 40, reason: 'the bookmark index under 1500 tokens: 1 listed, 0 left out', position: 1, text: '#1 2026-10-26 the garden' },
      ],
    },
  },
};

// The conversations list (kumbukumbu#40): a button in the top bar,
// "Conversations · 3", opens and closes it as a panel over the transcript.
export const WithConversations: Story = {
  args: { connection: 'connected', conversations: { sessions, chatKey: 'chat', current: 'chat', onOpen: () => undefined } },
};

// A Claude Code conversation open, reached from the list.
export const ReadOnlyFromTheList: Story = {
  args: { ...ReadOnly.args, conversations: { sessions, chatKey: 'chat', current: 'c2', onOpen: () => undefined } },
};

// The witness's message the moment it is sent, before the turn lands,
// with the reply already streaming (the chat-UI survey's third pattern).
export const Sending: Story = {
  args: {
    outbox: [{ ref: 'r-beans-0001', text: 'And the beans — did they take?\nThe second row looked thin.', state: 'writing', attempts: 1 }],
    connection: 'connected',
    streaming: { turnRef: 'r-beans-0001', text: 'They took, mostly. The second' },
  },
};

// The stream is down (brain#45): the dot says so, and a message that
// never reached the server waits under its own ref with Retry.
export const Offline: Story = {
  args: {
    connection: 'offline',
    outbox: [{ ref: 'r-weir-00001', text: 'Did you walk to the weir?', state: 'unsent', attempts: 2 }],
    onRetry: () => undefined,
    onDismiss: () => undefined,
  },
};

// A second message waits behind the first while the resident uses a tool.
export const Busy: Story = {
  args: {
    connection: 'connected',
    outbox: [
      { ref: 'r-first-0001', text: 'Bookmark the garden?', state: 'tool', detail: 'bookmark_add', attempts: 1 },
      { ref: 'r-second-002', text: 'And the beans?', state: 'queued', attempts: 1 },
    ],
  },
};

// The turn ran and no reply came: the words were kept, the notice says
// why, and the message can be sent again.
export const NotAnswered: Story = {
  args: {
    connection: 'connected',
    outbox: [{ ref: 'r-fail-00001', text: 'Are you there?', state: 'failed', error: 'nisaba_provider_failed', attempts: 1 }],
    onRetry: () => undefined,
    onDismiss: () => undefined,
  },
};
