import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';

/**
 * The operator's open items (apsu#31), for a super admin alone: they sit
 * at the top of the bell and count toward its number, so what waits on
 * whoever runs the platform lives where he already looks. Read every five
 * minutes; nobody else asks.
 */
export function useOperatorQueue() {
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const operator = (me.data?.roles ?? []).includes('super_admin');
  const queue = useQuery({ queryKey: ['operator', 'queue'], queryFn: api.operatorQueue, enabled: operator, refetchInterval: 300_000 });
  return operator ? (queue.data?.open ?? []) : [];
}
