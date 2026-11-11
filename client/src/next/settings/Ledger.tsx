import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { BudgetLine, SpendRow } from '../../api/types';
import { capLine, day, settingsKey } from './logic';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { Card, Field, Said, Select } from './common';
import * as css from './settings.css';
import { useAct } from './useAct';

/**
 * The ledger (spec §10): budget lines per purpose, each editable, with
 * the spend so far; spend by purpose, by model and by actor. Your key
 * is stored under Profiles, keys and connections.
 */
export function Ledger() {
  const { id } = useSubject();
  const setPage = useShell((s) => s.setPage);
  const ledger = useQuery({
    queryKey: settingsKey(id, 'ledger'),
    queryFn: () => api.ledger(id),
  });
  const [purpose, setPurpose] = useState<string | null>(null);
  const [cap, setCap] = useState('');
  const [period, setPeriod] = useState('month');
  const act = useAct();

  if (ledger.isPending) return <p className={css.note}>Reading…</p>;
  if (!ledger.data) return <p className={css.refused}>The ledger could not be read.</p>;
  const data = ledger.data;
  const chosen = purpose ?? data.purposes[0] ?? 'chat';
  const edit = (line: BudgetLine) => {
    setPurpose(line.purpose);
    setCap(line.cap ?? '');
    setPeriod(line.period);
  };

  return (
    <>
      <Card title="Your key">
        <p className={css.text}>{data.key.present ? `Stored since ${day(data.key.stored_at)}.` : 'No key stored: nothing can be asked of a model until one is.'}</p>
        <div>
          <button type="button" className={css.quiet} onClick={() => setPage('connections')}>
            {data.key.present ? 'Rotate it ›' : 'Store one ›'}
          </button>
        </div>
      </Card>

      <Card title="Budget lines">
        {data.budgets.length === 0 ? (
          <p className={css.note}>No lines yet: a purpose with no line has no limit.</p>
        ) : (
          <ul className={css.list} aria-label="Budget lines">
            {data.budgets.map((line) => (
              <li key={`${line.purpose}-${line.period}`} className={css.line}>
                <span>{line.purpose}</span>
                <span className={line.exceeded ? `${css.mono} ${css.warn}` : css.mono}>{capLine(line)}</span>
                <button type="button" className={css.quiet} onClick={() => edit(line)} aria-label={`Change the ${line.purpose} line`}>
                  Change
                </button>
              </li>
            ))}
          </ul>
        )}
        <form
          aria-label="Set a budget line"
          className={css.row}
          onSubmit={(e) => {
            e.preventDefault();
            void act.run(async () => {
              await api.setBudget(id, chosen, cap.trim() === '' ? null : cap.trim(), period);
              return cap.trim() === '' ? `${chosen} has no limit.` : `${chosen}: $${cap.trim()} a ${period}.`;
            });
          }}
        >
          <Select label="Purpose" value={chosen} onChange={setPurpose}>
            {data.purposes.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </Select>
          <Field label="Cap in dollars (blank for no limit)" value={cap} onChange={(e) => setCap(e.target.value)} inputMode="decimal" />
          <Select label="Per" value={period} onChange={setPeriod}>
            <option value="day">day</option>
            <option value="week">week</option>
            <option value="month">month</option>
          </Select>
          <button type="submit" className={css.primary} disabled={act.busy}>
            Set the line
          </button>
        </form>
        <Said said={act.said} />
      </Card>

      <p className={css.meta}>SPEND SINCE {day(data.spend.since)}</p>
      <Spend title="By purpose" rows={data.spend.by_purpose} />
      <Spend title="By model" rows={data.spend.by_model} />
      <Spend title="By actor" rows={data.spend.by_actor} />
    </>
  );
}

function Spend({ title, rows }: { title: string; rows: SpendRow[] }) {
  return (
    <Card title={title}>
      {rows.length === 0 ? (
        <p className={css.note}>Nothing spent yet.</p>
      ) : (
        <table className={css.table}>
          <thead>
            <tr>
              <th className={css.th}>{title.slice(3)}</th>
              <th className={css.th}>calls</th>
              <th className={`${css.th} ${css.num}`}>cost</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.key}>
                <td className={css.td}>
                  <span className={css.mono}>{r.key}</span>
                </td>
                <td className={`${css.td} ${css.mono}`}>{r.calls}</td>
                <td className={`${css.td} ${css.num}`}>${r.cost}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Card>
  );
}
