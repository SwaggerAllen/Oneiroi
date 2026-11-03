import type { Meta, StoryObj } from '@storybook/react-vite';
import { Connections } from './Connections';

const meta = {
  title: 'Screens/Connections',
  component: Connections,
  args: {
    residentName: 'Lily',
    adapters: [
      { adapter: 'claude-code', role: 'brain', registered_at: '2026-11-01T18:00:00Z', revoked_at: null },
      { adapter: 'laptop', role: 'brain', registered_at: '2026-10-30T18:00:00Z', revoked_at: '2026-11-01T18:00:00Z' },
    ],
    onRegister: () => undefined,
    onRevoke: () => undefined,
    onDismissToken: () => undefined,
  },
} satisfies Meta<typeof Connections>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Connected: Story = {};
export const TokenIssued: Story = { args: { issued: { adapter: 'scrape', token: 'oneiroi_reader_3f9c2b7a1d8e4f60b5a9c1e2d3f4a5b6' } } };
