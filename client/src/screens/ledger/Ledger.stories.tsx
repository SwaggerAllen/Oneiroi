import type { Meta, StoryObj } from '@storybook/react-vite';
import { Ledger } from './Ledger';
import type { Ledger as LedgerData } from '../../api/types';

const purposes = ['chat', 'free_time', 'judge', 'hands', 'embeddings', 'drafting', 'regression'];

const ledger: LedgerData = {
  key: { present: true, stored_at: '2026-10-26T12:00:00Z' },
  purposes,
  budgets: [
    { purpose: 'chat', period: 'month', cap: '20.00', spent: '3.41', exceeded: false },
    { purpose: 'regression', period: 'month', cap: '5.00', spent: '5.02', exceeded: true },
  ],
  spend: {
    since: '2026-10-01T00:00:00Z',
    by_purpose: [
      { key: 'chat', calls: 42, cost: '3.41' },
      { key: 'regression', calls: 8, cost: '5.02' },
    ],
    by_model: [{ key: 'openai/gpt-4o-mini', calls: 50, cost: '8.43' }],
    by_actor: [{ key: 'resident', calls: 42, cost: '3.41' }, { key: 'witness', calls: 8, cost: '5.02' }],
  },
};

const meta = {
  title: 'Screens/Ledger',
  component: Ledger,
  args: { ledger, onSetBudget: () => undefined, onStoreKey: () => undefined },
} satisfies Meta<typeof Ledger>;
export default meta;
type Story = StoryObj<typeof meta>;

export const NoKey: Story = {
  args: {
    ledger: {
      ...ledger,
      key: { present: false, stored_at: null },
      budgets: [],
      spend: { since: ledger.spend.since, by_purpose: [], by_model: [], by_actor: [] },
    },
  },
};
export const WithLines: Story = {};
export const Stopped: Story = {};
