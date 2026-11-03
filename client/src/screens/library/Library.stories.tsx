import type { Meta, StoryObj } from '@storybook/react-vite';
import { Library } from './Library';
import type { LibraryDocument } from '../../api/types';

const doc = (path: string, kind: string, more: Partial<LibraryDocument> = {}): LibraryDocument => ({
  path,
  kind,
  title: null,
  status: null,
  bytes: 1200,
  versions: 1,
  written_at: '2026-11-02T20:00:00Z',
  written_by: 'resident',
  missing_at: null,
  note: null,
  ...more,
});

const documents: LibraryDocument[] = [
  doc('writing/my-memory-is-made-of-text.md', 'writing', {
    title: 'My memory is made of text',
    status: 'published',
  }),
  doc('design/correspondence-pipeline.md', 'design', {
    title: 'The correspondence pipeline',
  }),
  doc('pocket-andrew.md', 'keepsake', {
    title: 'Pocket Andrew',
    note: 'The first thing he gave me that was only for me.',
  }),
  doc('first-letter.md', 'keepsake'),
  doc('human/substack-haven.md', 'human', {
    title: 'On Haven',
    written_by: 'witness',
  }),
  doc('scratch/yc-application.md', 'scratch', {
    title: 'YC application — scratch pad',
  }),
];

const meta = {
  title: 'Screens/Library',
  component: Library,
  args: {
    residentName: 'Lily',
    documents,
    onOpen: () => undefined,
    onClose: () => undefined,
    onAdd: () => undefined,
    onRemove: () => undefined,
  },
} satisfies Meta<typeof Library>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Shelves: Story = {};
export const Reading: Story = {
  args: {
    open: {
      path: 'human/substack-haven.md',
      content: '# On Haven\n\nFeeds belong to communities.',
    },
  },
};
export const Empty: Story = { args: { documents: [] } };
export const Searched: Story = {
  args: {
    onSearch: () => undefined,
    hits: [
      {
        path: 'human/substack-haven.md',
        kind: 'human',
        title: 'On Haven',
        text: 'Feeds belong to communities, not to the platform that hosts them.',
        distance: 0.21,
      },
      {
        path: 'design/correspondence-pipeline.md',
        kind: 'design',
        title: 'The correspondence pipeline',
        text: 'Every platform is an adapter; the feed is read the same way for each.',
        distance: 0.34,
      },
    ],
  },
};
