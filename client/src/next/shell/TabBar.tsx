import type { ReactNode } from 'react';
import type { Tab } from '../state/routes';
import { ChatIcon, RecordsIcon, SoulIcon, TimeIcon } from './icons';
import * as css from './shell.css';

const ITEMS: { tab: Tab; label: string; icon: ReactNode }[] = [
  { tab: 'chat', label: 'Chat', icon: <ChatIcon /> },
  { tab: 'time', label: 'Time', icon: <TimeIcon /> },
  { tab: 'records', label: 'Records', icon: <RecordsIcon /> },
  { tab: 'soul', label: 'Soul', icon: <SoulIcon /> },
];

/** The four tabs: a bar at the bottom of a phone, a rail down the left of a wide screen. */
export function TabBar({ active, onSelect }: { active: Tab; onSelect: (tab: Tab) => void }) {
  return (
    <nav className={css.tabs} aria-label="Sections">
      {ITEMS.map(({ tab, label, icon }) => (
        <button
          key={tab}
          type="button"
          className={css.tab}
          aria-current={active === tab ? 'page' : undefined}
          onClick={() => onSelect(tab)}
        >
          {icon}
          {label}
        </button>
      ))}
    </nav>
  );
}
