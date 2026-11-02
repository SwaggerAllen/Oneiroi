import type { Meta, StoryObj } from '@storybook/react-vite';
import { More } from './More';

const meta = {
  title: 'Screens/More',
  component: More,
  args: { onOpen: () => undefined },
} satisfies Meta<typeof More>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Built: Story = {};
