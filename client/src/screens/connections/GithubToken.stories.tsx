import type { Meta, StoryObj } from '@storybook/react-vite';
import { GithubToken } from './GithubToken';

const meta = {
  title: 'Screens/Connections/GitHub',
  component: GithubToken,
  args: { residentName: 'Lily', status: { present: false, stored_at: null }, onStore: () => undefined, onRevoke: () => undefined },
} satisfies Meta<typeof GithubToken>;
export default meta;
type Story = StoryObj<typeof meta>;

export const None: Story = {};
export const Stored: Story = { args: { status: { present: true, stored_at: '2026-11-08T23:00:00Z' } } };
