import type { Meta, StoryObj } from '@storybook/react-vite';
import { Operator } from './Operator';

const meta = {
  title: 'Screens/More/Operator',
  component: Operator,
  args: {
    platform: {
      gate: { state: 'closed', note: null, set_by: null, set_at: null },
      roles: [
        { account_id: 'a1', email: 'andrew@example.com', role: 'super_admin', note: 'the founding account', granted_by: 'platform', granted_at: '2026-11-05T18:00:00Z' },
      ],
    },
    onSetGate: () => undefined,
    onGrant: () => undefined,
    onRevoke: () => undefined,
  },
} satisfies Meta<typeof Operator>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Closed: Story = {};
export const InviteWithAnAdmin: Story = {
  args: {
    platform: {
      gate: { state: 'invite', note: 'the alpha', set_by: 'witness:a1', set_at: '2026-11-05T18:05:00Z' },
      roles: [
        { account_id: 'a1', email: 'andrew@example.com', role: 'super_admin', note: 'the founding account', granted_by: 'platform', granted_at: '2026-11-05T18:00:00Z' },
        { account_id: 'a2', email: 'helper@example.com', role: 'admin', note: 'helps with invites', granted_by: 'witness:a1', granted_at: '2026-11-05T18:10:00Z' },
      ],
    },
  },
};
