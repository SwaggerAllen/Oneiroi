import type { Meta, StoryObj } from '@storybook/react-vite';
import { Plugins } from './Plugins';
import type { PluginEntry } from '../../api/types';

const plugin = (key: string, name: string, more: Partial<PluginEntry> = {}): PluginEntry => ({
  key,
  name,
  about: `what ${name} is`,
  tier: 'first_party',
  place: 'turn',
  reads: [],
  installed: true,
  on: true,
  carried_over: true,
  changed_by: 'platform',
  changed_at: '2026-11-07T23:00:00Z',
  ...more,
});

const meta = {
  title: 'Screens/Agreement/Plugins',
  component: Plugins,
  args: {
    name: 'Lily',
    data: {
      plugins: [plugin('timeline', 'Your timeline'), plugin('exploration', 'Drawn at random'), plugin('honcho', 'Honcho', { on: false, carried_over: false })],
      proposals: [
        { number: 2, key: 'exploration', change: 'off', proposed_by: 'resident', note: 'a quiet week', proposed_at: '2026-11-07T23:10:00Z', agreed: null, answer_note: null, answered_at: null },
        { number: 1, key: 'honcho', change: 'off', proposed_by: 'witness', note: 'testing', proposed_at: '2026-11-07T23:00:00Z', agreed: true, answer_note: 'fine', answered_at: '2026-11-07T23:05:00Z' },
      ],
    },
    onPropose: () => undefined,
    onAnswer: () => undefined,
    onOff: () => undefined,
  },
} satisfies Meta<typeof Plugins>;
export default meta;
type Story = StoryObj<typeof meta>;

export const WithAProposal: Story = {};
