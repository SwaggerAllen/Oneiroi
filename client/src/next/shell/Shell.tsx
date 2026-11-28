import type { ReactNode } from 'react';
import { useEffect, useState } from 'react';
import { SettingsPage } from '../settings/SettingsPage';
import { formatHash, formatSettings, isTabHash, parseHash, parseSettings, parseSettingsPath, TABS, type Tab } from '../state/routes';
import { topOf, useShell } from '../state/store';
import { elsewhere, useUnread } from './unread';
import { Header } from './Header';
import { usePushSlide, useTabDissolve } from './motion';
import { OfflineBar } from './OfflineBar';
import { UpdateBar } from './UpdateBar';
import { Overlays } from './Overlays';
import { HouseSearchSheet } from './HouseSearchSheet';
import { SearchSheet } from './SearchSheet';
import * as css from './shell.css';
import { TabBar } from './TabBar';
import { DeliberationTabs } from '../succession/Deliberation';
import { useWide } from './useWide';

export interface ShellProps {
  residentId: string;
  residentName: string;
  waiting: number;
  failing?: boolean;
  onReconnect: () => void;
  /** Renders a tab at the top of its stack; every tab stays mounted. */
  renderTab: (tab: Tab, path: string) => ReactNode;
  /** The house's shell (screen:next-house): its own tab names, its own search (seshat#80). */
  house?: boolean;
}

/**
 * Keeps the URL and the stacks in step, both ways. A settings page
 * (`#/settings/<section>`) sits over the tabs: arriving at one opens it,
 * and leaving it (Back, a tab, the browser's back) returns the URL to
 * the tab underneath. Any other hash (`#/operator`) is left alone.
 */
function useHashSync() {
  const go = useShell((s) => s.go);
  const setPage = useShell((s) => s.setPage);
  const tab = useShell((s) => s.tab);
  const stacks = useShell((s) => s.stacks);
  const page = useShell((s) => s.page);
  const pagePath = useShell((s) => s.pagePath);

  useEffect(() => {
    const read = () => {
      const section = parseSettings(window.location.hash);
      if (section) setPage(section, parseSettingsPath(window.location.hash));
      else if (isTabHash(window.location.hash)) go(parseHash(window.location.hash));
    };
    read();
    window.addEventListener('hashchange', read);
    return () => window.removeEventListener('hashchange', read);
  }, [go, setPage]);

  useEffect(() => {
    const now = window.location.hash;
    if (!isTabHash(now) && !parseSettings(now)) return;
    const hash = page ? formatSettings(page, pagePath) : formatHash({ tab, path: topOf(stacks, tab) });
    if (now !== hash) window.history.pushState(null, '', hash);
  }, [tab, stacks, page, pagePath]);
}

export function Shell({ residentId, residentName, waiting, failing = false, onReconnect, renderTab, house = false }: ShellProps) {
  useHashSync();
  const unread = useUnread();
  const tab = useShell((s) => s.tab);
  const stacks = useShell((s) => s.stacks);
  const setTab = useShell((s) => s.setTab);
  const setOverlay = useShell((s) => s.setOverlay);
  const page = useShell((s) => s.page);
  const pagePath = useShell((s) => s.pagePath);
  const setPage = useShell((s) => s.setPage);
  const { leaving, ref } = useTabDissolve(tab);
  // The house queue is a subject of its own (the witness, 2026-11-23): its
  // name in the header, and no tabs under it.
  const work = page === 'queue';
  const wide = useWide();
  // On a wide screen Records and Time show the list beside the page, so
  // a push changes one pane, not the view: only the narrow layout slides.
  const [active, setActive] = useState<HTMLElement | null>(null);
  usePushSlide(active, stacks[tab].length, !wide);

  return (
    <div className={css.root}>
      <Header
        name={work ? 'Work' : residentName}
        waiting={waiting}
        failing={failing}
        unreadElsewhere={elsewhere(unread, residentId)}
        onSubject={() => setOverlay('subject')}
        onBell={() => setOverlay('bell')}
        onSettings={() => setOverlay('settings')}
      />
      <div className={css.bar}>
        <OfflineBar onReconnect={onReconnect} />
        <UpdateBar />
      </div>
      <main className={css.main}>
        {TABS.map((t) => (
          <section
            key={t}
            ref={(el) => {
              ref(t)(el);
              if (t === tab && el !== active) setActive(el);
            }}
            className={css.panel}
            hidden={page !== null || (t !== tab && t !== leaving)}
            data-leaving={t === leaving || undefined}
            aria-label={t}
            inert={page !== null || t !== tab}
          >
            {renderTab(t, topOf(stacks, t))}
          </section>
        ))}
        {page && (
          <section className={css.panel} aria-label="settings">
            <SettingsPage section={page} onBack={() => setPage(null)} />
          </section>
        )}
      </main>
      {/* The deliberation's own four tabs take the bar's place (screen:next-succession). */}
      {!work && (page === 'succession' && pagePath.startsWith('deliberation') ? <DeliberationTabs path={pagePath} /> : <TabBar active={tab} onSelect={setTab} house={house} />)}
      {house ? <HouseSearchSheet /> : <SearchSheet residentId={residentId} residentName={residentName} />}
      <Overlays />
    </div>
  );
}
