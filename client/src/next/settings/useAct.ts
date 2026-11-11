import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { useSubject } from '../state/resident';
import { saidOf } from './logic';

/**
 * One action at a time on a card: busy while it runs, then what it did
 * (or why it was refused) in a line, and the resident's settings read again.
 */
export function useAct() {
  const { id } = useSubject();
  const queries = useQueryClient();
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<{ text: string; refused: boolean } | null>(null);
  const run = (work: () => Promise<string | void>, ...also: unknown[][]) => {
    setBusy(true);
    setSaid(null);
    return work()
      .then((text) => setSaid(text ? { text, refused: false } : null))
      .catch((e: unknown) => setSaid({ text: saidOf(e), refused: true }))
      .finally(() => {
        setBusy(false);
        void queries.invalidateQueries({
          queryKey: ['resident', id, 'settings'],
        });
        for (const key of also) void queries.invalidateQueries({ queryKey: key });
      });
  };
  return { busy, said, run, clear: () => setSaid(null) };
}
