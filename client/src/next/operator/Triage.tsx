import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import { REPORT_STATUSES, statusWord } from './logic';
import { Card, Field, SaidLine } from './parts';
import { useOp } from './useOp';
import * as css from './operator.css';

const PLATFORM = ['operator', 'platform'];
const FEEDBACK = ['operator', 'feedback'];

/** Triage: who holds the desk (gaia#23), then the platform's reports (gaia#20). */
export function Triage() {
  return (
    <>
      <Desk />
      <Reports />
    </>
  );
}

/**
 * The triage desk: the resident who receives every platform report as a
 * letter and can move a report's status, or nobody. Each change carries
 * a note.
 */
function Desk() {
  const platform = useQuery({ queryKey: PLATFORM, queryFn: api.platform });
  const op = useOp();
  const [slug, setSlug] = useState('');
  const [note, setNote] = useState('');
  const t = platform.data?.triage;
  const set = (to: string | null) =>
    void op
      .run(() => api.setTriage(to, note.trim()).then(() => (to ? `${to} holds the triage desk.` : 'Nobody holds the triage desk.')), PLATFORM)
      .then((ok) => {
        if (!ok) return;
        setSlug('');
        setNote('');
      });
  return (
    <section className={css.card} aria-label="Triage desk">
      <h2 className={css.heading}>TRIAGE DESK</h2>
      <p>
        {t?.slug ? (
          <>
            <strong>{t.slug}</strong> receives every platform report as a letter and can move a report's status
            {t.from === 'environment' ? ', from GAIA_TRIAGE_RESIDENT on the server until it is set here' : t.note ? ` · ${t.note}` : ''}.
          </>
        ) : (
          'Nobody: reports wait here for the operator alone.'
        )}
      </p>
      <form
        className={css.form}
        onSubmit={(e) => {
          e.preventDefault();
          if (slug.trim() && note.trim()) set(slug.trim());
        }}
      >
        <div className={css.grid}>
          <Field label="Resident (slug)" value={slug} onChange={(e) => setSlug(e.target.value)} />
          <Field label="Why (recorded with the change)" value={note} onChange={(e) => setNote(e.target.value)} />
        </div>
        <div className={css.buttons}>
          <button type="submit" className={css.primary} disabled={op.busy || !slug.trim() || !note.trim()}>
            Set
          </button>
          <button type="button" className={css.button} disabled={op.busy || !note.trim() || !t?.slug} onClick={() => set(null)}>
            Nobody
          </button>
        </div>
      </form>
      <SaidLine said={op.said} />
    </section>
  );
}

/**
 * Every platform report, narrowed by status; one open with the failure
 * ring's entries for its trace id beside the reporter's words, and a
 * move with a note the reporter reads.
 */
function Reports() {
  const reports = useQuery({ queryKey: FEEDBACK, queryFn: api.allFeedback });
  const [status, setStatus] = useState<string>('new');
  const [open, setOpen] = useState<number | null>(null);
  const all = reports.data ?? [];
  // The open report stays in view after a move takes it out of the filter.
  const shown = status === 'all' ? all : all.filter((r) => r.status === status || r.number === open);
  return (
    <Card title={`REPORTS · ${all.length}`} label="Reports">
      <div role="group" aria-label="Status" className={css.buttons}>
        {[...REPORT_STATUSES, 'all'].map((s) => (
          <button key={s} type="button" className={css.filter} aria-pressed={status === s} onClick={() => setStatus(s)}>
            {statusWord(s)} {s === 'all' ? all.length : all.filter((r) => r.status === s).length}
          </button>
        ))}
      </div>
      {reports.isError && <p className={css.refused}>The reports didn't load.</p>}
      {reports.data && shown.length === 0 && <p className={css.note}>None.</p>}
      {shown.map((r) => (
        <div key={r.number} className={css.failure}>
          <button type="button" className={css.link} aria-expanded={open === r.number} onClick={() => setOpen(open === r.number ? null : r.number)}>
            #{r.number} {r.kind === 'bug' ? 'problem' : 'feature'}
            {r.surface ? ` · ${r.surface}` : ''} · {r.author_kind} · {statusWord(r.status)}
          </button>
          <span className={css.mono}>{new Date(r.filed_at).toLocaleString()}</span>
          {open === r.number ? <Report n={r.number} /> : <span className={css.clip}>{r.body}</span>}
        </div>
      ))}
    </Card>
  );
}

function Report({ n }: { n: number }) {
  const key = [...FEEDBACK, n];
  const detail = useQuery({
    queryKey: key,
    queryFn: () => api.feedbackReport(n),
  });
  const op = useOp();
  const [note, setNote] = useState('');
  const d = detail.data;
  if (detail.isError) return <p className={css.refused}>The report didn't load.</p>;
  if (!d) return <p className={css.note}>…</p>;
  return (
    <div className={css.detail} aria-label={`Report ${n}`}>
      <p className={css.reportBody}>{d.body}</p>
      <p className={css.note}>
        {statusWord(d.status)}
        {d.note ? `: ${d.note}` : ''}
        {d.trace_id ? ` · trace ${d.trace_id}` : ''}
      </p>
      {d.trace_id &&
        (d.failures.length ? (
          <ul aria-label="What the platform logged" className={css.logged}>
            {d.failures.map((f, i) => (
              <li key={i} className={css.mono}>
                {f.at} {f.level} {f.component ?? ''} {f.error_kind ?? ''} {f.error_site ?? ''}: {f.message}
              </li>
            ))}
          </ul>
        ) : (
          <p className={css.note}>The failure ring holds nothing for this trace id (it keeps the last 200, and empties on a restart).</p>
        ))}
      <Field label="A note the reporter reads (required)" value={note} onChange={(e) => setNote(e.target.value)} />
      <div className={css.buttons}>
        {REPORT_STATUSES.filter((s) => s !== d.status).map((s) => (
          <button
            key={s}
            type="button"
            className={css.button}
            disabled={op.busy || !note.trim()}
            onClick={() => void op.run(() => api.moveFeedback(n, s, note.trim()).then(() => `#${n} is ${statusWord(s)}.`), FEEDBACK).then((ok) => ok && setNote(''))}
          >
            Mark {statusWord(s)}
          </button>
        ))}
      </div>
      <SaidLine said={op.said} />
    </div>
  );
}
