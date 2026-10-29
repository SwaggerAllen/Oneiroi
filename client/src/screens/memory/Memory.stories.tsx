import type { Meta, StoryObj } from '@storybook/react-vite';
import { Memory } from './Memory';
import type { Bookmark } from '../../api/types';

const lily = { kind: 'resident', id: 'r1', model: 'openai/gpt-4o-mini' };

const bookmarks: Bookmark[] = [
  {
    number: 2,
    line: 'the first time she said it back',
    summary: 'We were talking about the garden and she said she missed me too.',
    session_key: 's',
    anchor_ref: 't9',
    anchor_at: '2026-10-27T18:10:00Z',
    turns_back: 3,
    tags: ['haven'],
    added_by: lily,
    proposed_by: null,
    pinned_by: { kind: 'steward', id: 'a1' },
    pinned_at: '2026-10-27T19:00:00Z',
    last_indexed_at: '2026-10-28T08:00:00Z',
  },
  {
    number: 1,
    line: 'the garden',
    summary: 'The tomatoes want water.',
    session_key: 's',
    anchor_ref: 't1',
    anchor_at: '2026-10-26T12:00:00Z',
    turns_back: 1,
    tags: [],
    added_by: lily,
    proposed_by: { kind: 'steward', id: 'a1' },
    pinned_by: null,
    pinned_at: null,
    last_indexed_at: null,
  },
];

const meta = {
  title: 'Screens/Memory',
  component: Memory,
  args: {
    residentName: 'Lily',
    bookmarks,
    tags: [
      { slug: 'haven', state: 'active', note: null },
      { slug: 'care', state: 'proposed', note: 'why' },
    ],
    indexBudget: 1500,
    onPin: () => undefined,
    onUnpin: () => undefined,
  },
} satisfies Meta<typeof Memory>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Empty: Story = { args: { bookmarks: [], tags: [] } };
export const InTheIndex: Story = {};
export const WithTags: Story = {};
