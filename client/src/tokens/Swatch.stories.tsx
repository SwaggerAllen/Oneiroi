import type { Meta, StoryObj } from '@storybook/react-vite';
import { Swatch } from './Swatch';

const meta = { title: 'Tokens/Swatch', component: Swatch } satisfies Meta<typeof Swatch>;
export default meta;
type Story = StoryObj<typeof meta>;

// One variation per state (conventions §9); a swatch has one.
export const Default: Story = {};
