import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { SaidLine } from './parts';
import { useOp } from './useOp';
import * as css from './operator.css';

/**
 * What the span collector keeps (apsu#26; the witness, 2026-11-13: every
 * unit while the platform is small, sampling toggleable and scalable
 * here), and the slowest units of the last day (apsu#28).
 */
export function Spans() {
  const platform = useQuery({ queryKey: ['operator', 'platform'], queryFn: api.platform });
  const slow = useQuery({ queryKey: ['operator', 'spans'], queryFn: () => api.opsSpans() });
  const op = useOp();
  const policy = platform.data?.span_policy;
  const [mode, setMode] = useState<'all' | 'sample' | null>(null);
  const [slowMs, setSlowMs] = useState('');
  const [percent, setPercent] = useState('');
  const [note, setNote] = useState('');
  const chosen = mode ?? policy?.mode ?? 'all';
  const slowValue = slowMs === '' ? (policy?.slow_ms ?? 250) : Number(slowMs);
  const percentValue = percent === '' ? (policy?.sample_percent ?? 1) : Number(percent);
  const valid = note.trim() !== '' && Number.isInteger(slowValue) && slowValue >= 0 && Number.isInteger(percentValue) && percentValue >= 0 && percentValue <= 100;

  return (
    <>
      <section className={css.card} aria-label="What spans are kept">
        <h2 className={css.heading}>SPANS KEPT</h2>
        <p>
          {policy?.mode === 'sample'
            ? `Sampling: units of ${policy.slow_ms} ms or more, failures, and ${policy.sample_percent}% of the rest are kept as rows.`
            : 'Every request, job and turn is kept as a row.'}{' '}
          The public hour counts every unit either way.
        </p>
        <div className={css.buttons} role="group" aria-label="Mode">
          <button type="button" className={chosen === 'all' ? css.primary : css.button} onClick={() => setMode('all')}>
            Keep every unit
          </button>
          <button type="button" className={chosen === 'sample' ? css.primary : css.button} onClick={() => setMode('sample')}>
            Sample
          </button>
        </div>
        {chosen === 'sample' && (
          <div className={css.inline}>
            <label className={css.field}>
              Slow from (ms)
              <input className={css.input} inputMode="numeric" value={slowMs === '' ? String(policy?.slow_ms ?? 250) : slowMs} onChange={(e) => setSlowMs(e.target.value)} />
            </label>
            <label className={css.field}>
              Sample of the rest (%)
              <input className={css.input} inputMode="numeric" value={percent === '' ? String(policy?.sample_percent ?? 1) : percent} onChange={(e) => setPercent(e.target.value)} />
            </label>
          </div>
        )}
        <input className={css.input} placeholder="Why (recorded with the change)" value={note} onChange={(e) => setNote(e.target.value)} aria-label="Note" />
        <div className={css.buttons}>
          <button
            type="button"
            className={css.primary}
            disabled={!valid || op.busy}
            onClick={() =>
              void op
                .run(() => api.setSpanPolicy(chosen, slowValue, percentValue, note.trim()).then((p) => (p.mode === 'all' ? 'Every unit is kept.' : `Sampling ${p.sample_percent}%, slow from ${p.slow_ms} ms.`)), ['operator', 'platform'])
                .then((ok) => ok && setNote(''))
            }
          >
            Set
          </button>
        </div>
        <SaidLine said={op.said} />
        {(platform.data?.span_policies ?? []).slice(0, 5).map((p) => (
          <p key={p.set_at} className={css.note}>
            {new Date(p.set_at).toLocaleString()} · {p.mode === 'all' ? 'every unit' : `sample ${p.sample_percent}%, slow ${p.slow_ms} ms`} — “{p.note}”
          </p>
        ))}
      </section>
      <section className={css.card} aria-label="Slowest units">
        <h2 className={css.heading}>SLOWEST, LAST DAY · {slow.data?.length ?? 0}</h2>
        {(slow.data ?? []).slice(0, 40).map((s, i) => (
          <div key={i} className={css.failure}>
            <span className={css.mono}>
              {new Date(s.at).toLocaleString()} · {s.kind} · {s.duration_ms} ms · queries {s.db_count} ({s.db_ms} ms) · pool wait {s.queue_ms} ms{s.failed ? ' · FAILED' : ''}
            </span>
            <span>{s.name}</span>
            <span className={css.mono}>
              {Object.entries(s.exports)
                .slice(0, 4)
                .map(([k, v]) => `${k} ${v.ms} ms`)
                .join(' · ')}
              {Object.keys(s.events).length > 0 ? ` · events: ${Object.entries(s.events).map(([k, v]) => `${k}×${v}`).join(', ')}` : ''}
            </span>
          </div>
        ))}
      </section>
    </>
  );
}
