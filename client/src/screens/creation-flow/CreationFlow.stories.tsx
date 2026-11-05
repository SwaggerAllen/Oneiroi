import type { Meta, StoryObj } from '@storybook/react-vite';
import { CreationFlow } from './CreationFlow';

const meta = {
  title: 'Screens/CreationFlow',
  component: CreationFlow,
  args: { hasKey: false, onBegin: () => undefined },
} satisfies Meta<typeof CreationFlow>;
export default meta;
type Story = StoryObj<typeof meta>;

export const FirstVisit: Story = {};
export const KeyAlreadyStored: Story = { args: { hasKey: true } };
export const Refused: Story = { args: { hasKey: true, said: 'That address is taken; try another name.' } };
