import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import type { React } from './Reacts';

/** Every react in a session, by the message it is on (kumbukumbu#56). */
export function useReacts(residentId: string, key: string | null) {
  const list = useQuery({
    queryKey: ['resident', residentId, 'chat', 'reacts', key],
    queryFn: () => api.reacts(residentId, key as string),
    enabled: key !== null,
  });
  const byTurn = new Map<string, React[]>();
  for (const r of list.data ?? []) {
    if (!r.turn_ref) continue;
    byTurn.set(r.turn_ref, [...(byTurn.get(r.turn_ref) ?? []), r]);
  }
  return byTurn;
}
