import { useQuery, useQueryClient } from '@tanstack/react-query';
import { pushState } from '../../app/push';

const DECLINED = 'oneiroi.next.push-declined';
const DECLINED_KEY = ['me', 'push-declined'];

function readDeclined(): boolean {
  try {
    return localStorage.getItem(DECLINED) === 'yes';
  } catch {
    return false;
  }
}

/**
 * Whether to ask about notifications: until the witness answers, either
 * way (ui-structures.md, decided 2026-11-10). The answer lives in the
 * query cache so the bell's count and the explainer agree at once; it is
 * kept on this device (the account-wide answer is S6's).
 */
export function useNotificationsAsk() {
  const queries = useQueryClient();
  const push = useQuery({ queryKey: ['me', 'push-state'], queryFn: pushState, staleTime: 60_000 });
  const declined = useQuery({ queryKey: DECLINED_KEY, queryFn: readDeclined, staleTime: Infinity });
  const ask = declined.data === false && (push.data === 'ready' || push.data === 'install');
  const decline = () => {
    try {
      localStorage.setItem(DECLINED, 'yes');
    } catch {
      // kept for this visit only
    }
    queries.setQueryData(DECLINED_KEY, true);
  };
  return { ask, state: push.data, decline };
}
