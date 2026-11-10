import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '../../api/client';
import { pushState } from '../../app/push';

/**
 * Whether to ask about notifications: until the witness's account answers,
 * either way, on any device (gaia#25; decided 2026-11-10). "No thanks" is
 * recorded on the account, so no other device asks again; subscribing
 * answers it too.
 */
export function useNotificationsAsk() {
  const queries = useQueryClient();
  const device = useQuery({ queryKey: ['me', 'push-state'], queryFn: pushState, staleTime: 60_000 });
  const config = useQuery({ queryKey: ['me', 'push-config'], queryFn: api.pushConfig, staleTime: 60_000 });
  const ask = config.data?.answered === null && (device.data === 'ready' || device.data === 'install');
  const declined = useMutation({
    mutationFn: api.declinePush,
    onSuccess: () => {
      void queries.invalidateQueries({ queryKey: ['me', 'push-config'] });
      void queries.invalidateQueries({ queryKey: ['resident'], predicate: (q) => q.queryKey.includes('bell') });
    },
  });
  return { ask, state: device.data, decline: () => declined.mutate() };
}
