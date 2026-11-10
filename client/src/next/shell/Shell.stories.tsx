import type { Meta, StoryObj } from '@storybook/react-vite';
import { useEffect } from 'react';
import { useShell, type Connection, type Presence } from '../state/store';
import { Theme } from '../theme/Theme';
import '../theme/contract.css';
import { Header } from './Header';
import { OfflineBar } from './OfflineBar';
import { TabBar } from './TabBar';

// The shell's pieces in each state the canvas drew (ChatLive, ChatOffline):
// one story per state, the state's name as the variation's.
function Frame({ presence, connection, children }: { presence: Presence; connection: Connection; children: React.ReactNode }) {
  useEffect(() => {
    useShell.setState({ presence, connection, offlineSince: connection === 'connected' ? null : Date.now() - 5000 });
  }, [presence, connection]);
  return (
    <Theme>
      <div style={{ width: 390, background: 'var(--ground, #0a0a10)' }}>{children}</div>
    </Theme>
  );
}

const meta: Meta = { title: 'Next/Shell' };
export default meta;

export const Idle: StoryObj = {
  render: () => (
    <Frame presence={{ state: 'idle', lastReply: '2026-11-10T09:02:00' }} connection="connected">
      <Header name="Lily" waiting={3} />
    </Frame>
  ),
};

export const UsingATool: StoryObj = {
  render: () => (
    <Frame presence={{ state: 'tool', detail: 'document_write', since: Date.now() - 14_000 }} connection="connected">
      <Header name="Lily" waiting={3} />
    </Frame>
  ),
};

export const Offline: StoryObj = {
  render: () => (
    <Frame presence={{ state: 'writing', since: Date.now() - 9_000 }} connection="offline">
      <Header name="Lily" waiting={0} />
      <OfflineBar onReconnect={() => undefined} />
    </Frame>
  ),
};

export const Tabs: StoryObj = {
  render: () => (
    <Frame presence={{ state: 'idle' }} connection="connected">
      <TabBar active="records" onSelect={() => undefined} />
    </Frame>
  ),
};
