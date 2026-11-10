import type { ReactNode } from 'react';
import { useEffect } from 'react';
import { formatHash, parseHash, TABS, type Tab } from '../state/routes';
import { topOf, useShell } from '../state/store';
import { Header } from './Header';
import { OfflineBar } from './OfflineBar';
import { Overlays } from './Overlays';
import { SearchSheet } from './SearchSheet';
import * as css from './shell.css';
import { TabBar } from './TabBar';

export interface ShellProps {
  residentId: string;
  residentName: string;
  waiting: number;
  onReconnect: () => void;
  /** Renders a tab at the top of its stack; every tab stays mounted. */
  renderTab: (tab: Tab, path: string) => ReactNode;
}

/** Keeps the URL and the stacks in step, both ways. */
function useHashSync() {
  const go = useShell((s) => s.go);
  const tab = useShell((s) => s.tab);
  const stacks = useShell((s) => s.stacks);

  useEffect(() => {
    const read = () => go(parseHash(window.location.hash));
    read();
    window.addEventListener('hashchange', read);
    return () => window.removeEventListener('hashchange', read);
  }, [go]);

  useEffect(() => {
    const hash = formatHash({ tab, path: topOf(stacks, tab) });
    if (window.location.hash !== hash) window.history.pushState(null, '', hash);
  }, [tab, stacks]);
}

export function Shell({ residentId, residentName, waiting, onReconnect, renderTab }: ShellProps) {
  useHashSync();
  const tab = useShell((s) => s.tab);
  const stacks = useShell((s) => s.stacks);
  const setTab = useShell((s) => s.setTab);
  const setOverlay = useShell((s) => s.setOverlay);

  return (
    <div className={css.root}>
      <Header name={residentName} waiting={waiting} onBell={() => setOverlay('bell')} onSettings={() => setOverlay('settings')} />
      <div className={css.bar}>
        <OfflineBar onReconnect={onReconnect} />
      </div>
      <main className={css.main}>
        {TABS.map((t) => (
          <section key={t} className={css.panel} hidden={t !== tab} aria-label={t} inert={t !== tab}>
            {renderTab(t, topOf(stacks, t))}
          </section>
        ))}
      </main>
      <TabBar active={tab} onSelect={setTab} />
      <SearchSheet residentId={residentId} residentName={residentName} />
      <Overlays />
    </div>
  );
}
