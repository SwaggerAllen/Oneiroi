import { useQueryClient } from '@tanstack/react-query';
import { useEffect, useMemo } from 'react';
import { LiveContext } from '../live/context';
import { Live } from '../live/live';
import { Shell } from '../shell/Shell';
import { useShell } from '../state/store';
import { DEFAULT_SEEDS } from '../theme/derive';
import { Charter } from './Charter';
import { HouseRecords } from './HouseRecords';
import { HouseTime } from './HouseTime';
import { Threads } from './Threads';

/**
 * The house as a subject (screen:next-house; the witness, 2026-11-16):
 * chosen from the residents' dropdown, the same shell and tabs, the soul
 * tab its charter. The house's own theme, nobody's in particular.
 */
export function HouseHome() {
  const setSeeds = useShell((s) => s.setSeeds);
  useEffect(() => setSeeds(DEFAULT_SEEDS), [setSeeds]);
  // The house's own socket: its pages join the household's channel on it
  // (the Work page, sunna#80); no resident's notices are watched here.
  const queries = useQueryClient();
  const live = useMemo(() => new Live(queries), [queries]);
  useEffect(() => {
    void live.start();
    return () => live.stop();
  }, [live]);
  return (
    <LiveContext.Provider value={live}>
      <Shell
        house
        residentId="house"
        residentName="The house"
        waiting={0}
        onReconnect={() => void live.reconnect()}
        renderTab={(tab, path) => (tab === 'chat' ? <Threads /> : tab === 'time' ? <HouseTime /> : tab === 'records' ? <HouseRecords path={path} /> : <Charter />)}
      />
    </LiveContext.Provider>
  );
}
