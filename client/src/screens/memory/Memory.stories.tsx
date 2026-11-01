import type { Meta, StoryObj } from '@storybook/react-vite';
import { Memory } from './Memory';
import type { Bookmark, IndexNow } from '../../api/types';

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
    pinned_by: { kind: 'witness', id: 'a1' },
    pinned_at: '2026-10-27T19:00:00Z',
    // No turn has listed it yet: the index tab reads the server's build,
    // never this mark.
    last_indexed_at: null,
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
    proposed_by: { kind: 'witness', id: 'a1' },
    pinned_by: null,
    pinned_at: null,
    last_indexed_at: '2026-10-20T08:00:00Z',
  },
];

// The server's words, as it sends them (kumbukumbu #38); the client
// renders them and restates nothing.
const index: IndexNow = {
  listed: [2],
  left_out: 1,
  elsewhere: 0,
  description:
    'What the next turn in the main conversation is given now: 1 bookmark listed under a budget of 40 tokens (a bound), pins first and taking at most half of it, then the rest by weight and recency. 1 left out for want of room; each is still opened by its number and reached by paging back.',
};

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
    index,
    onPin: () => undefined,
    onUnpin: () => undefined,
  },
} satisfies Meta<typeof Memory>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Empty: Story = {
  args: {
    bookmarks: [],
    tags: [],
    index: {
      listed: [],
      left_out: 0,
      elsewhere: 0,
      description:
        'What the next turn in the main conversation is given now: 0 bookmarks listed under a budget of 1500 tokens (a bound), pins first and taking at most half of it, then the rest by weight and recency.',
    },
  },
};
export const InTheIndex: Story = {};
export const IndexEmpty: Story = {
  args: {
    index: {
      listed: [],
      left_out: 0,
      elsewhere: 2,
      description:
        'What the next turn in the main conversation is given now: 0 bookmarks listed under a budget of 1500 tokens (a bound), pins first and taking at most half of it, then the rest by weight and recency. 2 bookmarks made in a named room are listed only in that room\'s conversations.',
    },
  },
};
export const WithTags: Story = {};
