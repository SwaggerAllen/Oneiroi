import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { saidOf } from '../settings/logic';

export type Said = { text: string; refused: boolean } | null;

/**
 * One operator action at a time on a card: busy while it runs, then what
 * it did (or the server's refusal) in a line, and the named reads again.
 * Resolves to whether it went through.
 */
export function useOp() {
  const queries = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<Said>(null);
  const run = (work: () => Promise<string | void>, ...also: unknown[][]) => {
    setBusy(true);
    setSaid(null);
    return work()
      .then((text) => {
        setSaid(text ? { text, refused: false } : null);
        return true;
      })
      .catch((e: unknown) => {
        setSaid({ text: saidOf(e), refused: true });
        return false;
      })
      .finally(() => {
        setBusy(false);
        for (const key of also) void queries.invalidateQueries({ queryKey: key });
      });
  };
  return { busy, said, run };
}
