import { useEffect } from 'react';
import { useLive } from '../live/context';
import { useShell } from '../state/store';

// The house queue's pages (screen:next-house) under `#/settings/queue/…`:
// each a path the browser's back steps through.

export type WorkRoute =
  | { page: 'list' }
  | { page: 'task'; number: number }
  | { page: 'activity'; number: number; act: string }
  | { page: 'new-activity'; number: number }
  | { page: 'new-task'; citation: string | null }
  | { page: 'template'; name: string }
  | { page: 'template-activity'; name: string; at: string }
  | { page: 'doc'; citation: string };

export const workPath = {
  task: (n: number) => `task/${n}`,
  activity: (n: number, act: string) => `task/${n}/act/${act}`,
  newActivity: (n: number) => `task/${n}/new`,
  newTask: (citation?: string) => (citation ? `new/${citation}` : 'new'),
  template: (name: string) => `template/${name}`,
  templateActivity: (name: string, at: string) => `template/${name}/act/${at}`,
  doc: (citation: string) => `doc/${citation}`,
};

/** A queue page's path to its route; anything unknown is the list. */
export function parseWorkPath(path: string): WorkRoute {
  const parts = path.split('/');
  const n = Number(parts[1]);
  if (parts[0] === 'task' && Number.isInteger(n) && n > 0) {
    if (parts[2] === 'act' && parts[3]) return { page: 'activity', number: n, act: parts.slice(3).join('/') };
    if (parts[2] === 'new') return { page: 'new-activity', number: n };
    return { page: 'task', number: n };
  }
  if (parts[0] === 'new') return { page: 'new-task', citation: parts.length > 1 ? parts.slice(1).join('/') : null };
  if (parts[0] === 'template' && parts[1]) {
    if (parts[2] === 'act' && parts[3]) return { page: 'template-activity', name: parts[1], at: parts[3] };
    return { page: 'template', name: parts[1] };
  }
  if (parts[0] === 'doc' && parts.length > 1) return { page: 'doc', citation: parts.slice(1).join('/') };
  return { page: 'list' };
}

/** Opens a queue page over whatever is showing: from Records too. */
export function useWorkNav(): (path: string) => void {
  const setPage = useShell((s) => s.setPage);
  return (path: string) => setPage('queue', path);
}

/** Joins the household's channel while the page is up (sunna#80, seshat#109); shared, never polled. */
export function useHouseLive(householdId: string | null | undefined) {
  const live = useLive();
  useEffect(() => (live && householdId ? live.house(householdId) : undefined), [live, householdId]);
}
