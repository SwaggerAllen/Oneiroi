import { useQuery } from '@tanstack/react-query';
import { useEffect } from 'react';
import { api } from '../../api/client';
import { useShell } from '../state/store';
import type { Seeds } from './derive';

// A device's own seeds for a resident (client-state.md: local theme
// overrides): kept here only, never sent; the witness's THEME.md stays
// what every other device shows.
const key = (residentId: string) => `oneiroi.theme.${residentId}`;

export function readOverride(residentId: string): Seeds | null {
  try {
    const raw = localStorage.getItem(key(residentId));
    return raw ? (JSON.parse(raw) as Seeds) : null;
  } catch {
    return null;
  }
}

export function writeOverride(residentId: string, seeds: Seeds | null) {
  try {
    if (seeds) localStorage.setItem(key(residentId), JSON.stringify(seeds));
    else localStorage.removeItem(key(residentId));
  } catch {
    // a private window: the override lasts this visit
  }
}

/** Puts the subject's seeds on screen: a try-on, else this device's override, else THEME.md (seshat#56). */
export function useResidentTheme(residentId: string) {
  const theme = useQuery({ queryKey: ['resident', residentId, 'theme'], queryFn: () => api.theme(residentId), staleTime: 5 * 60_000 });
  const tryOn = useShell((s) => s.tryOn);
  const setSeeds = useShell((s) => s.setSeeds);
  const override = useQuery({ queryKey: ['device', 'theme-override', residentId], queryFn: () => readOverride(residentId), staleTime: Infinity });
  const server = theme.data?.seeds;
  useEffect(() => {
    const seeds = tryOn ?? override.data ?? server;
    if (seeds) setSeeds(seeds);
  }, [tryOn, override.data, server, setSeeds]);
  return theme;
}
