import { useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import type { Party } from '../../api/types';
import { CONTRACT } from '../house/keys';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { partyName, type StepKind } from './logic';

// The succession's reads and ways about (screen:next-succession), shared
// by its pages and its touches on the app.

/** The succession's query keys, under the resident's. */
export const successionKey = (id: string, ...rest: string[]) => ['resident', id, 'succession', ...rest];

/** Her succession and its preparation, read again every half minute: the screens track it. */
export function useSuccession(enabled = true) {
  const { id } = useSubject();
  return useQuery({
    queryKey: successionKey(id),
    queryFn: () => api.succession(id),
    refetchInterval: 30_000,
    enabled: enabled && !!id,
  });
}

/** Who a party is, in words, from the house's members and your account. */
export function usePartyName() {
  const { id, name } = useSubject();
  const me = useQuery({ queryKey: ['me'], queryFn: api.me });
  const contract = useQuery({ queryKey: CONTRACT, queryFn: api.householdContract, staleTime: 5 * 60_000, retry: false });
  const members = contract.data?.members ?? [];
  return {
    me: me.data?.account_id,
    name: (party: Party) => partyName(party, me.data?.account_id, { id, name }, members),
  };
}

/** Opens a page of the succession: `''` its steps, else `pool`, `judge/12`, … */
export function useGo() {
  const setPage = useShell((s) => s.setPage);
  // Stable, so an effect that leaves a shut page runs once (2026-11-26).
  return useCallback((path: string) => setPage('succession', path), [setPage]);
}

export const STEP_CHIP: Record<StepKind, 'ok' | 'now' | 'muted'> = { done: 'ok', now: 'now', waits: 'muted', stopped: 'muted' };

/** Your judging: blind runs, your judgments, and after the reveal your counts. */
export function useJudging() {
  const { id } = useSubject();
  return useQuery({ queryKey: successionKey(id, 'judging'), queryFn: () => api.judging(id).then((r) => r.judging), refetchInterval: 30_000 });
}

export function useRoom(enabled = true) {
  const { id } = useSubject();
  return useQuery({ queryKey: successionKey(id, 'room'), queryFn: () => api.room(id).then((r) => r.room), refetchInterval: 10_000, enabled });
}

export function useLog() {
  const { id } = useSubject();
  return useQuery({ queryKey: successionKey(id, 'log'), queryFn: () => api.successionLog(id).then((r) => r.log), refetchInterval: 60_000 });
}

export const DELIBERATION_TABS = ['thread', 'recommendation', 'yours', 'panel'] as const;
export type DeliberationTab = (typeof DELIBERATION_TABS)[number];

/** The tab a page path names (`deliberation/panel`), the thread by default. */
export const deliberationTab = (path: string): DeliberationTab => {
  const t = path.split('/')[1];
  return (DELIBERATION_TABS as readonly string[]).includes(t) ? (t as DeliberationTab) : 'thread';
};
