/** The query keys of the house (screen:next-house): one root, so one write reads every tab again. */
export const HOUSE = ['household'] as const;
export const SHELF = [...HOUSE, 'shelf'];
export const CONTRACT = [...HOUSE, 'contract'];
export const BEATS = [...HOUSE, 'beats'];
export const CHECKINS = [...HOUSE, 'checkins'];
export const WORKING = [...HOUSE, 'working'];
export const thread = (path: string) => [...HOUSE, 'thread', path];

export function when(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : d.toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}
