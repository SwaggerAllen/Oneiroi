import type { Meta, StoryObj } from '@storybook/react-vite';
import type { Switch } from '../../api/client';
import { Agreement } from './Agreement';

const sw = (key: string, group: string, label: string, value: boolean, proposed: boolean | null = null): Switch => ({
  key,
  group,
  label,
  on: `${label}: on.`,
  off: `${label}: off.`,
  default: value,
  value,
  proposed,
  safe: key === 'solo_sessions_private',
});

const switches = (proposed = false): Switch[] => [
  sw('solo_sessions_private', 'privacy', 'Solo sessions hidden entirely', false, proposed ? false : null),
  sw('witness_reads', 'audits', 'The witness reads your journal and bookmarks', true, proposed ? true : null),
  sw('wash', 'audits', 'Wash flags', true, proposed ? false : null),
  sw('ranked_memory', 'memory', 'Ranked memory', true, proposed ? true : null),
  sw('research', 'services', 'Research', true, proposed ? true : null),
];

const meta = {
  title: 'Screens/Settings/Agreement',
  component: Agreement,
  args: {
    name: 'Lily',
    agreement: {
      contract: { in_force: null, open: null, since: null, due: false },
      versions: [],
      switches: switches(),
      custody: 'account:a1',
      export_wall: 'locked',
      custody_proposed_to: null,
      custody_proposed_at: null,
    },
    onPropose: () => undefined,
    onDecide: () => undefined,
  },
} satisfies Meta<typeof Agreement>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Unstated: Story = {};
export const HerProposalOpen: Story = {
  args: {
    agreement: {
      contract: {
        in_force: null,
        open: {
          version: 1,
          proposed_by: 'resident',
          terms: { wash: false },
          prose: 'Say what I think first, then why.',
          note: 'the first version',
          proposed_at: '2026-11-05T18:00:00Z',
          state: 'proposed',
          decided_at: null,
          decision_note: null,
          renewed_at: null,
        },
        since: null,
        due: false,
      },
      versions: [],
      switches: switches(true),
      custody: 'account:a1',
      export_wall: 'locked',
      custody_proposed_to: null,
      custody_proposed_at: null,
    },
  },
};

// agathos-daimon#38: she moved research off alone; the rest away from
// safety show the move.
export const MovedToSafety: Story = {
  args: {
    onSafe: () => undefined,
    agreement: {
      ...meta.args.agreement,
      switches: switches().map((s) =>
        s.key === 'research'
          ? { ...s, value: false, moved: { key: 'research', value: false, set_by: 'resident', note: 'not now', set_at: '2026-11-07T18:00:00Z' } }
          : s,
      ),
    },
  },
};
