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
/** The house's tabs are a resident's, its soul its charter (screen:next-house). */
const HOUSE_LABELS: Partial<Record<Tab, string>> = { soul: 'Charter' };

export function TabBar({ active, onSelect, house = false }: { active: Tab; onSelect: (tab: Tab) => void; house?: boolean }) {
  return <BottomTabs label="Sections" items={ITEMS.map(({ tab, label, icon }) => ({ key: tab, label: (house && HOUSE_LABELS[tab]) || label, icon }))} active={active} onSelect={onSelect} />;
}

/**
 * The bar itself, for any set of tabs: the shell's four, or a page's own
 * (the succession's deliberation, screen:next-succession) in their place.
 */
export function BottomTabs<K extends string>({ label, items, active, onSelect }: { label: string; items: { key: K; label: string; icon: ReactNode }[]; active: K; onSelect: (key: K) => void }) {
  return (
    <nav className={css.tabs} aria-label={label}>
      {items.map(({ key, label: name, icon }) => (
        <button key={key} type="button" className={css.tab} aria-current={active === key ? 'page' : undefined} onClick={() => onSelect(key)}>
          {icon}
          {name}
        </button>
      ))}
    </nav>
  );
}
