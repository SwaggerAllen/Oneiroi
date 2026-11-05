import type { Meta, StoryObj } from '@storybook/react-vite';
import { Notifications } from './Notifications';

const meta = {
  title: 'Screens/More/Notifications',
  component: Notifications,
  args: { residentName: 'Lily', state: 'ready', enabled: true, onTurnOn: () => undefined, onTurnOff: () => undefined, onTest: () => undefined },
} satisfies Meta<typeof Notifications>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Ready: Story = {};
export const On: Story = { args: { state: 'on', said: 'web.push.apple.com: delivered' } };
// An iPhone in Safari: the Home Screen app is the only place that may ask.
export const NeedsHomeScreen: Story = { args: { state: 'install' } };
export const Blocked: Story = { args: { state: 'denied' } };
export const NotSetUp: Story = { args: { enabled: false } };
export const Unsupported: Story = { args: { state: 'unsupported' } };
