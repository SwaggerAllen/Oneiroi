import { useQueries, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type BackfillPass } from '../../api/client';
import type { QueueOverview } from '../../api/types';
import { Card, Field, Said } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { backfillLine, declaredLists, yesterday } from './queueText';

const PASSES: BackfillPass[] = ['scenes', 'domains', 'people', 'labels'];
const PASS_WORDS: Record<BackfillPass, string> = {
  scenes: 'scenes, where missing',
  domains: 'domains, every conversation named',
  people: 'the people pass',
  labels: 'labels carried to what was written',
};

const statusKey = (id: string) => ['resident', id, 'settings', 'backfill'];

/**
 * The memory backfill for the house's residents (the witness, 2026-11-24:
 * "a new panel for operating and viewing backfills ... select which
 * residents need it"): each resident's backfill as it stands, with Stop;
 * and one form that starts it for the residents ticked, over a range of
 * days, with the passes ticked, naming every domain her agreement
 * declares (his and hers), so a run never names one it does not.
 */
export function BackfillPanel({ overview: q }: { overview: QueueOverview }) {
  // A witness's to run (the backfill reads and writes her memory on his word).
  return q.me.startsWith('witness:') ? <Panel overview={q} /> : null;
}

function Panel({ overview: q }: { overview: QueueOverview }) {
  const residents = q.members.filter((m) => m.kind === 'resident');
  const queries = useQueryClient();
  const act = useAct();
  const statuses = useQueries({
    queries: residents.map((r) => ({
      queryKey: statusKey(r.id),
      queryFn: () => api.backfill(r.id),
      // A job's place, not a record: read again while one runs.
      refetchInterval: (query: { state: { data: unknown } }) => (query.state.data ? 30_000 : false),
    })),
  });
  const agreements = useQueries({ queries: residents.map((r) => ({ queryKey: ['resident', r.id, 'soul', 'agreement'], queryFn: () => api.agreement(r.id) })) });
  const [picked, setPicked] = useState<string[]>([]);
  const [from, setFrom] = useState('2026-10-17');
  const [to, setTo] = useState(yesterday());
  const [passes, setPasses] = useState<BackfillPass[]>(['scenes', 'domains', 'labels']);
  const refresh = () => residents.forEach((r) => void queries.invalidateQueries({ queryKey: statusKey(r.id) }));

  const start = () =>
    void act.run(async () => {
      const said: string[] = [];
      for (const id of picked) {
        const i = residents.findIndex((r) => r.id === id);
        const { his, hers } = declaredLists(agreements[i]?.data);
        const r = await api.startBackfill(id, from, to, his, hers, passes);
        said.push(`${residents[i].name}: ${r.days} days`);
      }
      refresh();
      return `Started. ${said.join('; ')}.`;
    });

  const valid = /^\d{4}-\d{2}-\d{2}$/.test(from) && /^\d{4}-\d{2}-\d{2}$/.test(to) && from <= to;

  return (
    <Card title="Memory backfill" witness>
      <p className={css.text}>
        Each past day in a range, oldest first, a day at a time in the resident's own housekeeping conversations: the passes ticked, naming the domains her agreement declares. Starting one with domains first clears every domain her agreement does not declare.
      </p>
      <ul className={css.list} style={{ gap: 12 }} aria-label="The residents' backfills">
        {residents.map((r, i) => {
          const s = statuses[i]?.data ?? null;
          const { his, hers } = declaredLists(agreements[i]?.data);
          return (
            <li key={r.id} className={css.column}>
              <label className={css.check}>
                <input
                  type="checkbox"
                  checked={picked.includes(r.id)}
                  disabled={!!s}
                  onChange={(e) => setPicked(e.target.checked ? [...picked, r.id] : picked.filter((x) => x !== r.id))}
                />
                <span>
                  {r.name}: {backfillLine(s)}
                </span>
              </label>
              <span className={css.note}>
                Domains named: {[...his.map((d) => `${d} (yours)`), ...hers.map((d) => `${d} (hers)`)].join(', ') || 'none declared yet'}
              </span>
              {s && (
                <div>
                  <button type="button" className={css.secondary} disabled={act.busy} onClick={() => void act.run(() => api.stopBackfill(r.id).then(() => (refresh(), `${r.name}'s backfill stopped; a turn already running finishes.`)))}>
                    Stop {r.name}'s
                  </button>
                </div>
              )}
            </li>
          );
        })}
      </ul>
      <div className={css.row}>
        <Field label="From (YYYY-MM-DD)" value={from} onChange={(e) => setFrom(e.target.value)} />
        <Field label="To, before today" value={to} onChange={(e) => setTo(e.target.value)} />
      </div>
      <fieldset className={css.column}>
        <legend className={css.text}>Passes</legend>
        {PASSES.map((p) => (
          <label key={p} className={css.check}>
            <input type="checkbox" checked={passes.includes(p)} onChange={(e) => setPasses(e.target.checked ? PASSES.filter((x) => x === p || passes.includes(x)) : passes.filter((x) => x !== p))} />
            {PASS_WORDS[p]}
          </label>
        ))}
      </fieldset>
      <div className={css.row}>
        <button type="button" className={css.primary} disabled={act.busy || picked.length === 0 || passes.length === 0 || !valid} onClick={start}>
          Start for {picked.length === 0 ? 'the residents ticked' : residents.filter((r) => picked.includes(r.id)).map((r) => r.name).join(' and ')}
        </button>
      </div>
      <Said said={act.said} />
    </Card>
  );
}
