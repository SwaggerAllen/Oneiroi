import type { LibraryDocument } from '../../api/types';

/** How Records orders its folders and files; the default is the last write, newest first. */
export type RecordsOrder = 'updated' | 'updated-oldest' | 'added' | 'name';

export const ORDERS: Array<{ id: RecordsOrder; label: string }> = [
  { id: 'updated', label: 'Recently updated' },
  { id: 'updated-oldest', label: 'Least recently updated' },
  { id: 'added', label: 'Newest added' },
  { id: 'name', label: 'Name' },
];

const time = (iso: string | null | undefined) => (iso ? new Date(iso).getTime() : 0);
const updated = (d: LibraryDocument) => time(d.written_at ?? d.created_at);
const added = (d: LibraryDocument) => time(d.created_at ?? d.written_at);
const byName = (a: LibraryDocument, b: LibraryDocument) => a.path.localeCompare(b.path);

/** The documents in `order`; ties, and documents with no date, fall back to the path. */
export function sortDocs(docs: LibraryDocument[], order: RecordsOrder): LibraryDocument[] {
  const keyed = docs.slice();
  switch (order) {
    case 'updated':
      return keyed.sort((a, b) => updated(b) - updated(a) || byName(a, b));
    case 'updated-oldest':
      return keyed.sort((a, b) => updated(a) - updated(b) || byName(a, b));
    case 'added':
      return keyed.sort((a, b) => added(b) - added(a) || byName(a, b));
    default:
      return keyed.sort(byName);
  }
}

/** A folder's place in `order`: by its newest (or oldest) document's date, or by its name. */
export function folderKey(docs: LibraryDocument[], order: RecordsOrder): number {
  if (docs.length === 0) return order === 'updated-oldest' ? Infinity : -Infinity;
  switch (order) {
    case 'updated':
      return Math.max(...docs.map(updated));
    case 'updated-oldest':
      return Math.min(...docs.map(updated));
    case 'added':
      return Math.max(...docs.map(added));
    default:
      return 0;
  }
}

/** The date a row shows for `order`: when it was added under "Newest added", otherwise its last write. */
export function shownDate(d: LibraryDocument, order: RecordsOrder): string | null {
  const iso = order === 'added' ? (d.created_at ?? d.written_at) : (d.written_at ?? d.created_at);
  if (!iso) return null;
  const at = new Date(iso);
  const now = new Date();
  // Today's changes by the clock, so a busy day's order still reads.
  if (at.toDateString() === now.toDateString()) return at.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  const sameYear = at.getFullYear() === now.getFullYear();
  return at.toLocaleDateString(undefined, sameYear ? { month: 'short', day: 'numeric' } : { year: 'numeric', month: 'short', day: 'numeric' });
}

const KEY = 'oneiroi.records.order';

/** The order this device last chose, or the default. */
export function savedOrder(): RecordsOrder {
  try {
    const v = localStorage.getItem(KEY);
    return ORDERS.some((o) => o.id === v) ? (v as RecordsOrder) : 'updated';
  } catch {
    return 'updated';
  }
}

export function saveOrder(order: RecordsOrder) {
  try {
    localStorage.setItem(KEY, order);
  } catch {
    // A private window keeps no choice; the default stands next time.
  }
}
