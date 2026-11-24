import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type BackfillPass } from '../../api/client';
import type { WorkQueue } from '../../api/types';
import { useSubject } from '../state/resident';
import { workPath } from '../house/workRoutes';
import { Card, Field, Said } from './common';
import * as css from './settings.css';
import { useAct } from './useAct';
import { useNow } from '../shell/presence';
import { LONG_RUN_SECONDS, loopLine, runSeconds, settingsKey } from './logic';

/**
 * Her work line (sunna#33, #86): what it runs from the house queue now and
 * why it rests, its runs, today's and each activity's (sunna#101), and the
 * witness's two levers, giving the runs back (sunna#53) and letting work go
 * ahead of a free-time pass (sunna#76). Her work itself is in Work; the old
 * queue's items are retired (sunna#102).
 */
export function Work() {
  const { id, name } = useSubject();
  const work = useQuery({
    queryKey: settingsKey(id, 'work'),
    queryFn: () => api.work(id),
  });
  const [resetNote, setResetNote] = useState('');
  const [skipNote, setSkipNote] = useState('');
  const act = useAct();
  const run = (work: () => Promise<string>) => void act.run(work, ['resident', id, 'sessions'], ['resident', id, 'bell']);

  if (work.isPending) return <p className={css.note}>Reading…</p>;
  if (!work.data) return <p className={css.refused}>The work line could not be read.</p>;
  const q = work.data;
  const counted = q.activity_runs ?? [];

  return (
    <>
      <Card title="The work line" witness>
        <LoopLine name={name} q={q} />
        {q.running_act && q.running_task !== null && (
          <div>
            <a className={css.link} href={`#/settings/queue/${workPath.task(q.running_task)}`}>
              Open task #{q.running_task} ›
            </a>
          </div>
        )}
        <span className={css.note}>{name}'s line runs while the house queue runs; it is paused or resumed for everyone on the Work page.</span>
        {q.cut && (
          <span className={css.note}>
            Her last run of {q.cut.act} was cut off by the platform (a restart or a crash){q.cut.at ? ` at ${q.cut.at.slice(0, 16).replace('T', ' ')} UTC` : ''}; its next run is told where it got to.
          </span>
        )}
        {!q.running_act && (q.rested ?? '').startsWith('waiting: a free-time pass') && (
          <div className={css.column}>
            <span className={css.note}>
              Waiting on {name}'s free time (care comes first). You can let work go ahead of this pass; a later pass still comes first.
            </span>
            <Field label="Why work goes ahead (she reads it)" value={skipNote} onChange={(e) => setSkipNote(e.target.value)} />
            <div>
              <button
                type="button"
                className={css.secondary}
                disabled={act.busy}
                onClick={() =>
                  run(() =>
                    api.skipWorkCare(id, skipNote.trim() || 'Work goes ahead of this free-time pass.').then(() => {
                      setSkipNote('');
                      return 'Work goes ahead; the loop checks now.';
                    }),
                  )
                }
              >
                Start work now
              </button>
            </div>
          </div>
        )}
        {(q.runs_today > 0 || counted.length > 0) && (
          <div className={css.column}>
            <span className={css.note}>
              {q.runs_today} of {q.runs_a_day} runs used today.
              {counted.length > 0 &&
                ` Since each last moved: ${counted.map((a) => `${a.act} ${a.runs} of ${q.runs_an_activity ?? 20}`).join(', ')}; an activity at its limit is passed by until it moves or the runs come back.`}
            </span>
            <Field label="Why the runs come back (she reads it)" value={resetNote} onChange={(e) => setResetNote(e.target.value)} />
            <div>
              <button
                type="button"
                className={css.secondary}
                disabled={act.busy || resetNote.trim() === ''}
                onClick={() =>
                  run(() =>
                    api.resetWorkRuns(id, resetNote.trim()).then(() => {
                      setResetNote('');
                      return "The runs are back, today's and each activity's; the loop checks now.";
                    }),
                  )
                }
              >
                Give the runs back
              </button>
            </div>
          </div>
        )}
        <div>
          <a className={css.link} href="#/settings/queue">
            Open Work ›
          </a>
        </div>
        <Said said={act.said} />
      </Card>
      <Backfill />
    </>
  );
}

/**
 * The memory backfill (sunna#59): {name} writes the scenes, names the
 * domains (from your list and hers) and runs the people pass for each past
 * day in a range, oldest first, a day at a time, in housekeeping
 * conversations of her own. Started and stopped here; where it is, read
 * off its queued job.
 */
function Backfill() {
  const { id, name } = useSubject();
  const status = useQuery({ queryKey: settingsKey(id, 'backfill'), queryFn: () => api.backfill(id), refetchInterval: 30_000 });
  const [from, setFrom] = useState('2026-10-17');
  const [to, setTo] = useState('');
  // Only declared domains (kumbukumbu#90): his and hers, picked, never typed.
  const agreement = useQuery({ queryKey: ['resident', id, 'soul', 'agreement'], queryFn: () => api.agreement(id) });
  const persons = agreement.data?.persons;
  const declared = agreement.data?.domains ?? [];
  const yours = [...new Set(declared.filter((d) => d.person === persons?.witness).map((d) => d.domain))].sort();
  const theirs = [...new Set(declared.filter((d) => d.person === persons?.resident).map((d) => d.domain))].sort();
  const [his, setHis] = useState<string[]>([]);
  const [hers, setHers] = useState<string[]>([]);
  // One kind of pass at a time, or several (sunna#79): the domains pass
  // alone re-names past days without rewriting scenes or portraits.
  const [passes, setPasses] = useState<BackfillPass[]>(['scenes', 'domains', 'people', 'labels']);
  const act = useAct();
  const s = status.data;
  const PASS = { scenes: 'writing the scenes', domains: 'naming the domains', people: 'the people pass', labels: 'carrying the domains to what was written from them' } as const;
  return (
    <Card title="Memory backfill" witness>
      <p className={css.text}>
        {s
          ? `Running: ${PASS[s.pass]} for ${s.day}${s.turn > 1 ? ` (turn ${s.turn})` : ''}, through ${s.to}${s.passes && s.passes.length < 4 ? `; passes: ${s.passes.join(', ')}` : ''}.`
          : `For each past day in a range, oldest first, the passes you tick: ${name} writes its scenes where they are missing; names the domains of every conversation that day, from the declared domains you pick (tags of undeclared ones go back to the common room first); and runs the people pass, whose seeds become portraits; a day at a time, each a housekeeping conversation of hers, billed to chat. Then, once over the whole range and with no model, the labels pass carries those domains to what was written from the conversations (files, journal rows, letters) and down every citation.`}
      </p>
      {s ? (
        <div className={css.row}>
          <button type="button" className={css.secondary} disabled={act.busy} onClick={() => void act.run(() => api.stopBackfill(id).then(() => 'Stopped; a turn already running finishes.'), settingsKey(id, 'backfill'))}>
            Stop the backfill
          </button>
        </div>
      ) : (
        <form
          className={css.column}
          aria-label="Start the backfill"
          onSubmit={(e) => {
            e.preventDefault();
            void act.run(
              () => api.startBackfill(id, from, to, his, hers, passes).then((r) => `Started: ${r.days} days.`),
              settingsKey(id, 'backfill'),
            );
          }}
        >
          <div className={css.row}>
            <Field label="From (YYYY-MM-DD)" value={from} onChange={(e) => setFrom(e.target.value)} />
            <Field label="To, before today" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <fieldset className={css.column}>
            <legend className={css.text}>Passes</legend>
            {(['scenes', 'domains', 'people', 'labels'] as const).map((p) => (
              <label key={p} className={css.row}>
                <input type="checkbox" checked={passes.includes(p)} onChange={(e) => setPasses(e.target.checked ? (['scenes', 'domains', 'people', 'labels'] as const).filter((x) => x === p || passes.includes(x)) : passes.filter((x) => x !== p))} />
                {PASS[p]}
              </label>
            ))}
          </fieldset>
          <DomainPicks label="Your domains" options={yours} picked={his} onChange={setHis} />
          <DomainPicks label={`${name}'s domains`} options={theirs} picked={hers} onChange={setHers} />
          <div className={css.row}>
            <button type="submit" className={css.primary} disabled={act.busy || passes.length === 0 || !/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)}>
              Start the backfill
            </button>
          </div>
        </form>
      )}
      <Said said={act.said} />
    </Card>
  );
}

// Declared domains as choices (kumbukumbu#90): the agreement says which exist.
function DomainPicks({ label, options, picked, onChange }: { label: string; options: string[]; picked: string[]; onChange: (p: string[]) => void }) {
  return (
    <fieldset className={css.column}>
      <legend className={css.text}>{label}</legend>
      {options.length === 0 ? (
        <span className={css.text}>None declared in the agreement yet.</span>
      ) : (
        options.map((slug) => (
          <label key={slug} className={css.row}>
            <input
              type="checkbox"
              checked={picked.includes(slug)}
              onChange={(e) => onChange(e.target.checked ? [...picked, slug] : picked.filter((s) => s !== slug))}
            />
            {slug}
          </label>
        ))
      )}
    </fieldset>
  );
}

// The line, ticking while an activity runs so its time stays true; a run
// past an hour is marked for a look (sunna#58).
function LoopLine({ name, q }: { name: string; q: WorkQueue }) {
  const now = useNow(q.running_act != null);
  const run = runSeconds(q, now);
  const long = run !== null && run >= LONG_RUN_SECONDS;
  return (
    <p className={long ? `${css.text} ${css.warn}` : css.text}>
      {loopLine(name, q, now)}
      {long ? ' Running long: worth a look.' : ''}
    </p>
  );
}
