import type { Meta, StoryObj } from '@storybook/react-vite';
import { Invites } from './Invites';

const meta = {
  title: 'Screens/More/Invites',
  component: Invites,
  args: {
    invites: [],
    defaults: { plan: 'monthly', price_nanos: 20_000_000_000, discount_pct: 100, term_days: 90, uses: 1, expires_at: null },
    onIssue: () => undefined,
    onRevoke: () => undefined,
  },
} satisfies Meta<typeof Invites>;
export default meta;
type Story = StoryObj<typeof meta>;

export const NoneYet: Story = {};
export const JustIssued: Story = {
  args: {
    issued: 'K7QM-4XRT-9PWD',
    invites: [
      {
        id: 'i2',
        plan: 'monthly',
        list_price_nanos: 20_000_000_000,
        discount_pct: 100,
        price_nanos: 0,
        term_days: 90,
        uses: 1,
        redeemed: 0,
        expires_at: null,
        note: 'for Grace',
        issued_at: '2026-11-05T19:30:00Z',
        revoked_at: null,
        revoke_note: null,
      },
      {
        id: 'i1',
        plan: 'annual',
        list_price_nanos: 20_000_000_000,
        discount_pct: 50,
        price_nanos: 10_000_000_000,
        term_days: 365,
        uses: 5,
        redeemed: 5,
        expires_at: null,
        note: 'the meetup',
        issued_at: '2026-11-05T19:00:00Z',
        revoked_at: null,
        revoke_note: null,
      },
    ],
  },
};
