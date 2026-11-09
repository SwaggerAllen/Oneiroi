import type { Meta, StoryObj } from '@storybook/react-vite';
import { Kinds } from './Kinds';
import type { KindEntry } from '../../api/types';

const kind = (k: string, label: string, more: Partial<KindEntry> = {}): KindEntry => ({
  kind: k,
  label,
  folder: k,
  own: false,
  approvable: false,
  gated: false,
  cites: true,
  created_by: null,
  updated_by: null,
  ...more,
});

const meta = {
  title: 'Screens/Kinds',
  component: Kinds,
  args: {
    name: 'Lily',
    data: {
      kinds: [
        kind('writing', 'Writing', { approvable: true, gated: true }),
        kind('design', 'Design', { gated: true }),
        kind('notes', 'Notes'),
        kind('field-notes', 'Field notes', { own: true, approvable: true, created_by: 'resident', updated_by: 'resident' }),
      ],
      proposals: [
        { number: 2, kind: 'writing', approvable: false, proposed_by: 'resident', note: 'drafts can go straight out', proposed_at: '2026-11-09T10:00:00Z', agree: null, answered_by: null, answer_note: null, answered_at: null },
        { number: 1, kind: 'design', approvable: true, proposed_by: 'witness', note: 'I want to see designs', proposed_at: '2026-11-08T10:00:00Z', agree: true, answered_by: 'witness', answer_note: null, answered_at: '2026-11-08T10:00:00Z' },
      ],
    },
  },
} satisfies Meta<typeof Kinds>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Shelf: Story = {};

export const NoProposals: Story = { args: { data: { kinds: [kind('writing', 'Writing', { approvable: true, gated: true })], proposals: [] } } };
