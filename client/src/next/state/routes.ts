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
