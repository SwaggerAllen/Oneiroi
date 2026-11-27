import { useQuery } from '@tanstack/react-query';
import { useMemo, useState } from 'react';
import { api } from '../../api/client';
import { useSuccession } from '../succession/hooks';
import { PoolButton } from '../succession/Touches';
import { preparing, price, when } from '../succession/logic';
import { useSubject } from '../state/resident';
import { type CatalogFilter, type CatalogSort, findIn, monthly, narrowed, NO_FILTER, providers } from './finder';
import { Card } from './common';
import * as css from './settings.css';

/** How many models one screenful shows; "Show more" adds as many again. */
const PAGE = 30;

const SORTS: { value: CatalogSort; label: string }[] = [
  { value: 'cheapest', label: 'Cheapest first' },
  { value: 'monthly', label: 'Cheapest a month at her pace' },
  { value: 'dearest', label: 'Dearest first' },
  { value: 'context', label: 'Longest context' },
  { value: 'measured', label: 'Best tool calls on Oneiroi' },
  { value: 'name', label: 'By name' },
];

const CONTEXTS = [32_000, 128_000, 200_000, 1_000_000];

/**
 * The model catalog on Regression (screen:regression): each model's
 * prices, the provider's own blurb, and its tool calls on Oneiroi
 * measured nightly; searched and filtered here, a screenful at a time
 * (the witness, 2026-11-26: too big to navigate by scrolling). While
 * her succession's preparation is open, each entry adds to its pool
 * (screen:next-succession), and the envelope is a filter.
 */
export function Catalog() {
  const catalog = useQuery({ queryKey: ['catalog'], queryFn: () => api.catalog().then((r) => r.models), staleTime: 10 * 60_000 });
  const succession = useSuccession();
  const { name } = useSubject();
  const prep = preparing(succession.data?.succession) ? (succession.data?.preparation ?? null) : null;
  const env = prep?.envelope ?? null;
  // Her pace and her model now, while preparation is open (janus#38).
  const pace = prep?.pace ?? null;
  const current = prep?.current ?? null;
  const [f, setF] = useState<CatalogFilter>(NO_FILTER);
  const [shown, setShown] = useState(PAGE);
  const set = (patch: Partial<CatalogFilter>) => {
    setF((now) => ({ ...now, ...patch }));
    setShown(PAGE);
  };
  const models = useMemo(() => catalog.data ?? [], [catalog.data]);
  const found = useMemo(() => findIn(models, { ...f, envelope: f.envelope && !!env }, env, pace), [models, f, env, pace]);
  const makers = useMemo(() => providers(models), [models]);
  const fetched = models.map((m) => m.fetched_at).filter(Boolean).sort().pop();
  return (
    <>
      <h2 className={css.heading}>The catalog · OpenRouter{fetched ? `, fetched ${when(fetched)}` : ''}</h2>
      {catalog.isPending && <p className={css.note}>Reading…</p>}
      {catalog.error && <p className={css.refused}>The catalog could not be read.</p>}
      {catalog.data && models.length === 0 && <p className={css.note}>The catalog has not been fetched yet.</p>}
      {models.length > 0 && (
        <div className={css.card} role="search" aria-label="Find in the catalog">
          <label className={css.field}>
            Search
            <input className={css.input} type="search" value={f.query} placeholder="A name, a slug, a word from the blurb" onChange={(e) => set({ query: e.target.value })} />
          </label>
          <div className={css.row}>
            <label className={css.field}>
              Provider
              <select className={css.input} value={f.provider} onChange={(e) => set({ provider: e.target.value })}>
                <option value="">Every provider</option>
                {makers.map((p) => (
                  <option key={p.name} value={p.name}>
                    {p.name} ({p.count})
                  </option>
                ))}
              </select>
            </label>
            <label className={css.field}>
              Sort
              <select className={css.input} value={f.sort} onChange={(e) => set({ sort: e.target.value as CatalogSort })}>
                {SORTS.filter((s) => s.value !== 'monthly' || pace).map((s) => (
                  <option key={s.value} value={s.value}>
                    {s.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className={css.row}>
            <label className={css.field}>
              Output at most, $ per M
              <input
                className={css.input}
                type="number"
                min={0}
                step="any"
                inputMode="decimal"
                value={f.maxOutput ?? ''}
                placeholder="No cap"
                onChange={(e) => set({ maxOutput: e.target.value === '' ? null : Number(e.target.value) })}
              />
            </label>
            <label className={css.field}>
              Context at least
              <select className={css.input} value={f.minContext ?? ''} onChange={(e) => set({ minContext: e.target.value === '' ? null : Number(e.target.value) })}>
                <option value="">Any</option>
                {CONTEXTS.map((c) => (
                  <option key={c} value={c}>
                    {c.toLocaleString()} tokens
                  </option>
                ))}
              </select>
            </label>
          </div>
          <label className={css.check}>
            <input type="checkbox" checked={f.tools} onChange={(e) => set({ tools: e.target.checked })} />
            Takes tool calls (the only models she can run on)
          </label>
          <label className={css.check}>
            <input type="checkbox" checked={f.measured} onChange={(e) => set({ measured: e.target.checked })} />
            Tool calls measured on Oneiroi
          </label>
          {pace && (
            <p className={css.note}>
              {name}'s pace: spent ~{price(pace.monthly_spent)} a month
              {current?.monthly_estimate != null ? ` · ${current.model} now, ~${price(current.monthly_estimate)} a month at its list prices` : current ? ` · ${current.model} now, not in the catalog` : ''}
            </p>
          )}
          {env && (
            <label className={css.check}>
              <input type="checkbox" checked={f.envelope} onChange={(e) => set({ envelope: e.target.checked })} />
              Inside the succession's envelope ({price(env.input_per_million)} / {price(env.output_per_million)} per M)
            </label>
          )}
          <div className={css.row}>
            <span className={css.note} aria-live="polite">
              {found.length === models.length ? `All ${models.length.toLocaleString()} models` : `${found.length.toLocaleString()} of ${models.length.toLocaleString()} models`}
            </span>
            {narrowed(f) && (
              <button type="button" className={css.quiet} onClick={() => set({ ...NO_FILTER, sort: f.sort })}>
                Clear
              </button>
            )}
          </div>
        </div>
      )}
      {catalog.data && models.length > 0 && found.length === 0 && <p className={css.note}>Nothing in the catalog matches.</p>}
      {found.slice(0, shown).map((m) => (
        <Card key={m.model} title={m.model} label={m.model}>
          <p className={css.note}>
            {m.name ? `${m.name} · ` : ''}
            {price(m.input_per_million)} / {price(m.output_per_million)} per M{m.context ? ` · ${m.context.toLocaleString()} context` : ''}
          </p>
          {pace && m.tools && <p className={css.note}>~{price(monthly(m, pace))} a month at {name}'s pace</p>}
          {m.description && <p className={css.note}>“{m.description}” (provider's blurb)</p>}
          <p className={css.note}>
            {!m.tools
              ? 'Takes no tool calls: not supported for her.'
              : m.tool_calls
                ? `Tool calls on Oneiroi: ${Math.round((100 * (m.tool_calls - m.tool_calls_failed)) / m.tool_calls)}% well-formed · ${m.tool_calls.toLocaleString()} calls`
                : 'Tool calls on Oneiroi: none measured yet'}
          </p>
          {m.tools && <PoolButton model={m} />}
        </Card>
      ))}
      {found.length > shown && (
        <button type="button" className={css.secondary} onClick={() => setShown((n) => n + PAGE)}>
          Show {Math.min(PAGE, found.length - shown)} more of {(found.length - shown).toLocaleString()}
        </button>
      )}
      <p className={css.note}>Tool calls measured nightly from the day before's, kept as running totals: independent of anyone's judgments of her.</p>
    </>
  );
}
