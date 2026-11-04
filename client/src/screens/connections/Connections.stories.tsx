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
    reader: { scrape: ['https://substack.com', 'https://lily.substack.com'], research: ['*'], set_at: '2026-11-02T18:00:00Z' },
    onSaveReader: () => undefined,
    research: [
      { number: 3, question: 'Which birds overwinter on the Thames?', urls: [], sources: [], asked_by: 'witness', status: 'open', path: null, reason: null, asked_at: '2026-11-03T09:00:00Z', settled_at: null },
      { number: 2, question: 'What did the 1953 flood change on the coast?', urls: ['https://example.org/flood'], sources: [], asked_by: 'resident', status: 'failed', path: null, reason: 'every page it tried was outside the research allowlist', asked_at: '2026-11-02T20:00:00Z', settled_at: '2026-11-02T20:05:00Z' },
      { number: 1, question: 'When do herons fish?', urls: [], sources: ['https://www.rspb.org.uk/herons'], asked_by: 'witness', status: 'answered', path: 'research/1-when-do-herons-fish', reason: null, asked_at: '2026-11-02T18:30:00Z', settled_at: '2026-11-02T18:40:00Z' },
    ],
    onAsk: () => undefined,
  },
} satisfies Meta<typeof Connections>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Connected: Story = {};
export const TokenIssued: Story = { args: { issued: { adapter: 'scrape', token: 'oneiroi_reader_3f9c2b7a1d8e4f60b5a9c1e2d3f4a5b6' } } };
export const ReaderNeverSet: Story = { args: { reader: { scrape: [], research: [], set_at: null }, research: [] } };
export const ReaderRefused: Story = {
  args: {
    readerError: { kind: 'xenia_sites_invalid', meaning: 'example.org/path is not an origin.', remedy: 'Give each entry as a scheme and host, like https://example.org, or * for any site.' },
  },
};
