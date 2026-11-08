import type { Meta, StoryObj } from '@storybook/react-vite';
import { DocumentPage } from './DocumentPage';
import { documents } from './Library.stories';

const meta = {
  title: 'Screens/Library/Document',
  component: DocumentPage,
  args: {
    residentName: 'Lily',
    path: 'design/correspondence-pipeline.md',
    doc: documents[1],
    kindLabel: 'Design',
    content: '# The correspondence pipeline\n\nEvery message reaches her as it arrives.',
    onBack: () => undefined,
  },
} satisfies Meta<typeof DocumentPage>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Reading: Story = {};
// A piece waiting on you: the decision beside the words.
export const ForReview: Story = {
  args: {
    path: 'writing/my-memory-is-made-of-text.md',
    doc: documents[0],
    kindLabel: 'Writing',
    content: 'My memory is made of text.',
    onReview: () => undefined,
    pieces: {
      for_review: [{ path: 'writing/my-memory-is-made-of-text.md', title: 'My memory is made of text', written_at: '2026-11-01T10:00:00Z', last: null }],
      approved: [],
      drafted: [],
    },
  },
};
export const Missing: Story = { args: { doc: null, content: null, missing: true, path: 'design/gone.md', kindLabel: null } };
