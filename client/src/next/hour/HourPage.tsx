import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import * as css from '../onboarding/onboarding.css';
import { bars, count, ms, unitName } from './hour';

/**
 * The last hour, public (apsu#29; the witness, 2026-11-13: transparency, a
 * granular breakdown rather than a status light). Counts and timings in
 * five-minute buckets, never content, nothing per resident, and a count
 * under five read as "few". Open to anyone at #/hour.
 */
export function HourPage() {
  const hour = useQuery({ queryKey: ['hour'], queryFn: api.hour, refetchInterval: 60_000 });
  const h = hour.data;
  return (
    <div className={css.page}>
      <main className={css.column}>
        <div className={css.top}>
          <a className={css.brand} href="#/" style={{ textDecoration: 'none' }}>
            Oneiroi
          </a>
        </div>
        <p className={css.eyebrow}>How the platform ran</p>
        <h1 className={css.h1}>The last hour</h1>
        <p className={css.body}>
          Every request, job and turn, counted in five-minute buckets and refreshed as each closes. Times, never words; nothing about any one person. While the platform
          is small a count can be a person, so any count under {h?.few_below ?? 5} reads “few”.
        </p>
        {hour.isPending && <p className={css.note}>Reading…</p>}
        {hour.error && <p className={css.note}>The hour could not be read.</p>}
        {h && (
          <>
            <p className={css.note}>
              {new Date(h.window.from).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} to{' '}
              {new Date(h.window.to).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} · next at{' '}
              {new Date(h.next_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
              {h.commit ? ` · running ${h.commit}` : ''}
              {h.deployed_at ? ` since ${new Date(h.deployed_at).toLocaleString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' })}` : ''}
            </p>
            <section className={css.section} aria-label="Trend">
              <h2 className={css.h2}>Work per five minutes</h2>
              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, height: 64 }} role="img" aria-label="Units of work per bucket, oldest first">
                {bars(h.trend).map((v, i) => (
                  <div
                    key={h.trend[i].at}
                    title={`${new Date(h.trend[i].at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}: ${count(h.trend[i].units)} units, p95 ${ms(h.trend[i].p95_ms)}`}
                    style={{ flex: 1, height: `${Math.max(v * 100, 3)}%`, background: 'currentColor', opacity: 0.35, borderRadius: 2 }}
                  />
                ))}
              </div>
            </section>
            <section className={css.section} aria-label="Units of work">
              <h2 className={css.h2}>By unit of work, slowest first</h2>
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                  <thead>
                    <tr style={{ textAlign: 'left' }}>
                      <th>What</th>
                      <th>Count</th>
                      <th>Failed</th>
                      <th>p50</th>
                      <th>p95</th>
                      <th>In queries</th>
                      <th>Waiting for a connection</th>
                    </tr>
                  </thead>
                  <tbody>
                    {h.work.map((w) => (
                      <tr key={`${w.kind}-${w.name}`}>
                        <td style={{ padding: '4px 8px 4px 0', overflowWrap: 'anywhere' }}>
                          <span className={css.tag}>{w.kind}</span> {unitName(w.kind, w.name)}
                        </td>
                        <td>{count(w.units)}</td>
                        <td>{count(w.failed)}</td>
                        <td>{ms(w.p50_ms)}</td>
                        <td>{ms(w.p95_ms)}</td>
                        <td>{ms(w.mean_db_ms)}</td>
                        <td>{ms(w.mean_pool_wait_ms)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {h.work.length === 0 && <p className={css.note}>Nothing has run in the last hour yet.</p>}
            </section>
            {h.pressure && (
              <section className={css.section} aria-label="Pressure">
                <h2 className={css.h2}>Pressure now</h2>
                <p className={css.body}>
                  {h.pressure.jobs_waiting ?? 0} background jobs waiting
                  {h.pressure.oldest_wait_s ? `, the oldest for ${h.pressure.oldest_wait_s} s` : ''}.{' '}
                  {Object.keys(h.pressure.failures_by_kind).length === 0
                    ? 'No failures logged this hour.'
                    : `Failures logged this hour, by kind: ${Object.entries(h.pressure.failures_by_kind)
                        .map(([k, v]) => `${k} ${count(v)}`)
                        .join(', ')}.`}
                </p>
              </section>
            )}
          </>
        )}
      </main>
    </div>
  );
}
