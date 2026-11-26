import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { PoolButton } from '../succession/Touches';
import { price, when } from '../succession/logic';
import { Card } from './common';
import * as css from './settings.css';

/**
 * The model catalog on Regression (screen:regression): each model's
 * prices, the provider's own blurb, and its tool calls on Oneiroi
 * measured nightly. While her succession's preparation is open, each
 * entry adds to its pool (screen:next-succession).
 */
export function Catalog() {
  const catalog = useQuery({ queryKey: ['catalog'], queryFn: () => api.catalog().then((r) => r.models), staleTime: 10 * 60_000 });
  const models = catalog.data ?? [];
  const fetched = models.map((m) => m.fetched_at).filter(Boolean).sort().pop();
  return (
    <>
      <h2 className={css.heading}>The catalog · OpenRouter{fetched ? `, fetched ${when(fetched)}` : ''}</h2>
      {catalog.isPending && <p className={css.note}>Reading…</p>}
      {catalog.error && <p className={css.refused}>The catalog could not be read.</p>}
      {catalog.data && models.length === 0 && <p className={css.note}>The catalog has not been fetched yet.</p>}
      {models.map((m) => (
        <Card key={m.model} title={m.model} label={m.model}>
          <p className={css.note}>
            {m.name ? `${m.name} · ` : ''}
            {price(m.input_per_million)} / {price(m.output_per_million)} per M{m.context ? ` · ${m.context.toLocaleString()} context` : ''}
          </p>
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
      <p className={css.note}>Tool calls measured nightly from the day before's, kept as running totals: independent of anyone's judgments of her.</p>
    </>
  );
}
