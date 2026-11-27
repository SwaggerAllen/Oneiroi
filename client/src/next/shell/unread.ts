import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { HOUSE_SUBJECT } from '../state/resident';
import { PUSHED_FALLBACK_MS } from '../live/notices';

/**
 * What the witness has not read, by workspace (gaia#58, seshat#96; the
 * witness, 2026-11-19): a count for the house and for each resident's
 * chat, from the server's "seen up to" marks, so every device agrees.
 */
export function useUnread() {
  const q = useQuery({ queryKey: ['unread'], queryFn: api.unread, refetchInterval: PUSHED_FALLBACK_MS });
  const counts: Record<string, number> = {};
  for (const r of q.data?.residents ?? []) counts[r.id] = r.count;
  if (q.data?.house) counts[HOUSE_SUBJECT] = q.data.house.count;
  return counts;
}

/** Unread anywhere but the workspace on screen: the header's dot. */
export const elsewhere = (counts: Record<string, number>, current: string) =>
  Object.entries(counts).some(([subject, n]) => subject !== current && n > 0);
