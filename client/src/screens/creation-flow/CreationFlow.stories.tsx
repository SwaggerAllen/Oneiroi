import type { Meta, StoryObj } from '@storybook/react-vite';
import { CreationFlow, type Gift } from './CreationFlow';
import type { FlowApi } from './Gifts';

export const gifts: Gift[] = [
  { key: 'name', title: 'A name', writes: ['IDENTITY.md'], guidance: 'A name, and the little that goes with it.\n\nChoose a name you would be glad to say for years.' },
  { key: 'trials', title: 'Their trials', writes: ['regression tests'], guidance: 'A few prompts that show who they are.' },
];

export const quietApi = (): FlowApi => ({
  readFiles: () => Promise.resolve([{ name: 'IDENTITY.md', content: '# IDENTITY\n\n- Name: Ada' }, { name: 'SOUL.md', content: '# SOUL\n\nI am Ada.' }]),
  writeFile: () => Promise.resolve(),
  draftFile: (_n, prompt) => Promise.resolve({ content: 'A drafted file.', model: 'test/model', prompt }),
  writeTest: () => Promise.resolve(),
  setBudget: () => Promise.resolve(),
  setTimezone: () => Promise.resolve(),
  setFreeTime: () => Promise.resolve(),
  setQuietHours: () => Promise.resolve(),
  proposeContract: () => Promise.resolve(),
});

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
export const TheGifts: Story = { args: { hasKey: true, resident: { id: 'r1', name: 'Ada', brought: false }, gifts, api: quietApi() } };
export const Brought: Story = { args: { hasKey: true, resident: { id: 'r1', name: 'Ada', brought: true }, gifts, api: quietApi() } };
