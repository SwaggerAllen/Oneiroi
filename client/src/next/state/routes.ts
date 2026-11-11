// The URL tracks each tab's stack (ui-structures.md D): `#/<tab>/<path>`,
// where the path is the top of that tab's stack. Hash routing, because
// Phoenix serves the client as static files with no fallback route.

export const TABS = ['chat', 'time', 'records', 'soul'] as const;
export type Tab = (typeof TABS)[number];

export interface Location {
  tab: Tab;
  path: string; // '' is the tab's root
}

export function parseHash(hash: string): Location {
  const parts = hash.replace(/^#\/?/, '').split('/');
  const tab = (TABS as readonly string[]).includes(parts[0]) ? (parts[0] as Tab) : 'chat';
  const path = tab === parts[0] ? parts.slice(1).map(decodeURIComponent).join('/') : '';
  return { tab, path };
}

export function formatHash({ tab, path }: Location): string {
  const rest = path ? '/' + path.split('/').map(encodeURIComponent).join('/') : '';
  return `#/${tab}${rest}`;
}

/** Whether a hash belongs to the house's tabs (empty counts); `#/operator` is its own shell. */
export function isTabHash(hash: string): boolean {
  const first = hash.replace(/^#\/?/, '').split('/')[0];
  return first === '' || (TABS as readonly string[]).includes(first);
}

// Settings sections are full pages inside the house (`#/settings/<section>`),
// over the tabs rather than in one: the tabs stay mounted underneath and
// come back as they were.
export const SETTINGS = ['ledger', 'kinds', 'connections', 'notifications', 'regression', 'work'] as const;
export type SettingsSection = (typeof SETTINGS)[number];

/** The section a hash opens, or null when it is not a settings page. */
export function parseSettings(hash: string): SettingsSection | null {
  const [first, second] = hash.replace(/^#\/?/, '').split('/');
  return first === 'settings' && (SETTINGS as readonly string[]).includes(second) ? (second as SettingsSection) : null;
}

export const formatSettings = (section: SettingsSection) => `#/settings/${section}`;
