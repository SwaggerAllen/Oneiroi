import type { Meta, StoryObj } from '@storybook/react-vite';
import { Routes } from './Routes';
import type { ProfileEntry, RouteEntry } from '../../api/types';

const route = (key: string, label: string, more: Partial<RouteEntry> = {}): RouteEntry => ({
  key,
  label,
  direction: 'source',
  profile: 'research',
  kind: 'research',
  cadence: 'on_request',
  runner: key,
  built_in: true,
  state: 'ready',
  why: null,
  ...more,
});

const profile = (key: string, label: string, more: Partial<ProfileEntry> = {}): ProfileEntry => ({
  key,
  label,
  origin: null,
  signed_in_as: null,
  browser: null,
  sites: [],
  connector: null,
  seeded: true,
  revoked: false,
  routes: [],
  ...more,
});

const meta = {
  title: 'Screens/Connections/Routes',
  component: Routes,
  args: {
    name: 'Lily',
    data: {
      routes: [
        route('correspondence-out', 'Substack replies out', { direction: 'sink', profile: 'substack', kind: 'correspondence', cadence: 'on_approval', state: 'unable', why: 'its profile substack is revoked' }),
        route('research', 'Research'),
        route('marsh', 'marsh', { built_in: false, kind: 'field-notes', prompt: 'Herons at the marsh this week.', runner: 'route' }),
      ],
      runs: [{ number: 1, key: 'marsh', state: 'landed', note: null, asked_by: 'resident', asked_at: '2026-11-09T10:00:00Z', path: 'field-notes/marsh-1.md', reason: null, done_at: '2026-11-09T10:05:00Z' }],
      profiles: [
        profile('substack', 'Substack', { origin: 'https://substack.com', browser: 'browser-profile', sites: ['https://substack.com'], revoked: true, routes: ['correspondence-in', 'correspondence-out'] }),
        profile('research', 'Research, signed in nowhere', { browser: 'research-profile', sites: ['https://example.org'], routes: ['research', 'marsh'] }),
      ],
      landing: ['scratch', 'field-notes'],
    },
  },
} satisfies Meta<typeof Routes>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Registry: Story = {};
