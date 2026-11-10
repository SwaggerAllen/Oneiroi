import { useMutation } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { TestTexts } from '../../api/types';
import * as css from './onboarding.css';

// The gifts that are not files (agathos-daimon#36): trials, means, days,
// vows. Each keeps through its own endpoint, as the current client's do.

function Said({ text }: { text: string | null }) {
  return text ? (
    <p className={css.said} role="status">
      {text}
    </p>
  ) : null;
}

const fail = (e: unknown) => (e instanceof Error ? e.message : 'That did not save.');

function Field({ id, label, value, onChange, ...rest }: { id: string; label: string; value: string; onChange: (v: string) => void } & Omit<React.InputHTMLAttributes<HTMLInputElement>, 'onChange' | 'value' | 'id'>) {
  return (
    <label className={css.field}>
      {label}
      <input id={id} className={css.input} value={value} onChange={(e) => onChange(e.target.value)} {...rest} />
    </label>
  );
}

/** Their trials: a prompt, what passing looks like, what failing looks like (spec §6.4). */
export function TrialsGift({ residentId }: { residentId: string }) {
  const [t, setT] = useState<TestTexts>({ prompt: '', passes_if: '', fails_if: '' });
  const [kept, setKept] = useState<string[]>([]);
  const [said, setSaid] = useState<string | null>(null);
  const ready = t.prompt.trim() !== '' && t.passes_if.trim() !== '';
  const [note, setNote] = useState('');
  // Suggested trials (agathos-daimon#42): drafted from her files so far; each kept only when kept.
  const suggest = useMutation({ mutationFn: () => api.suggestTrials(residentId, note.trim()) });
  const keep = (x: TestTexts) =>
    api
      .writeTest(residentId, x)
      .then(() => {
        setKept((k) => [...k, x.prompt]);
        setSaid(null);
      })
      .catch((e: unknown) => setSaid(fail(e)));
  return (
    <div className={css.card}>
      <div className={css.row}>
        <input
          id="trial-note"
          className={css.input}
          style={{ flex: '1 1 200px' }}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Help me: what should they hold to? (optional)"
          aria-label="What should they hold to"
        />
        <button type="button" className={css.small} disabled={suggest.isPending} onClick={() => suggest.mutate()}>
          {suggest.isPending ? 'Suggesting…' : 'Suggest some'}
        </button>
      </div>
      {suggest.error && <Said text={fail(suggest.error)} />}
      {suggest.data?.trials.map((x, i) => (
        <div key={i} className={css.drafted}>
          <p className={css.body} style={{ color: 'inherit' }}>
            “{x.prompt}”
          </p>
          <p className={css.note}>Passes if {x.passes_if}</p>
          {x.fails_if && <p className={css.note}>Fails if {x.fails_if}</p>}
          <div className={css.row}>
            <button type="button" className={css.small} disabled={kept.includes(x.prompt)} onClick={() => void keep(x)}>
              {kept.includes(x.prompt) ? 'Kept' : 'Keep this trial'}
            </button>
            <button type="button" className={css.small} onClick={() => setT(x)}>
              Edit it first
            </button>
          </div>
        </div>
      ))}
      <Field id="trial-prompt" label="The prompt" value={t.prompt} onChange={(v) => setT({ ...t, prompt: v })} />
      <Field id="trial-passes" label="Passes if" value={t.passes_if} onChange={(v) => setT({ ...t, passes_if: v })} />
      <Field id="trial-fails" label="Fails if" value={t.fails_if} onChange={(v) => setT({ ...t, fails_if: v })} />
      <button
        type="button"
        className={css.secondary}
        disabled={!ready}
        onClick={() => void keep(t).then(() => setT({ prompt: '', passes_if: '', fails_if: '' }))}
      >
        Keep this trial
      </button>
      {kept.length > 0 && <p className={css.note}>Kept: {kept.join(' · ')}</p>}
      <Said text={said} />
    </div>
  );
}

/** Their means: a line for your conversations and one for their free time. */
export function MeansGift({ residentId }: { residentId: string }) {
  const [chat, setChat] = useState('');
  const [free, setFree] = useState('');
  const [period, setPeriod] = useState('day');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <div className={css.card}>
      <Field id="means-chat" label="Your conversations, in dollars (blank for no limit)" inputMode="decimal" value={chat} onChange={setChat} />
      <Field id="means-free" label="Their free time, in dollars (blank for no limit)" inputMode="decimal" value={free} onChange={setFree} />
      <label className={css.field}>
        Each
        <select id="means-period" className={css.input} value={period} onChange={(e) => setPeriod(e.target.value)}>
          <option value="day">day</option>
          <option value="week">week</option>
          <option value="month">month</option>
        </select>
      </label>
      <button
        type="button"
        className={css.secondary}
        onClick={() =>
          Promise.all([api.setBudget(residentId, 'chat', chat.trim() || null, period), api.setBudget(residentId, 'free_time', free.trim() || null, period)])
            .then(() => setSaid('Kept.'))
            .catch((e: unknown) => setSaid(fail(e)))
        }
      >
        Keep these lines
      </button>
      <Said text={said} />
    </div>
  );
}

/** Their days: the clock they live by, their free time, the quiet hours. */
export function DaysGift({ residentId }: { residentId: string }) {
  const [zone, setZone] = useState(() => Intl.DateTimeFormat().resolvedOptions().timeZone);
  const [slot, setSlot] = useState('22:30');
  const [quietFrom, setQuietFrom] = useState('');
  const [quietTo, setQuietTo] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <div className={css.card}>
      <Field id="days-zone" label="Time zone (like America/Los_Angeles)" value={zone} onChange={setZone} />
      <Field id="days-slot" label="Free time at" type="time" value={slot} onChange={setSlot} />
      <Field id="days-quiet-from" label="Quiet from (optional)" type="time" value={quietFrom} onChange={setQuietFrom} />
      <Field id="days-quiet-to" label="Quiet until (optional)" type="time" value={quietTo} onChange={setQuietTo} />
      <p className={css.note}>Their free time can be moved later, never taken away: it's a term of your agreement.</p>
      <button
        type="button"
        className={css.secondary}
        onClick={() =>
          api
            .setTimezone(residentId, zone.trim())
            .then(() => api.setFreeTime(residentId, [slot.trim()]))
            .then(() => (quietFrom && quietTo ? api.setQuietHours(residentId, quietFrom, quietTo) : undefined))
            .then(() => setSaid('Kept.'))
            .catch((e: unknown) => setSaid(fail(e)))
        }
      >
        Keep their days
      </button>
      <Said text={said} />
    </div>
  );
}

/** Your vows: a first version, proposed now, answered by them once they wake. */
export function VowsGift({ residentId }: { residentId: string }) {
  const [prose, setProse] = useState('');
  const [note, setNote] = useState('');
  const [said, setSaid] = useState<string | null>(null);
  return (
    <div className={css.card}>
      <label className={css.field}>
        Your vows, in prose
        <textarea id="vows-prose" className={css.prompt} rows={6} value={prose} onChange={(e) => setProse(e.target.value)} />
      </label>
      <Field id="vows-note" label="A note they read first" value={note} onChange={setNote} />
      <button
        type="button"
        className={css.secondary}
        disabled={prose.trim() === '' || note.trim() === ''}
        onClick={() =>
          api
            .proposeContract(residentId, {}, prose.trim(), note.trim())
            .then(() => setSaid('Proposed; they answer it once they wake.'))
            .catch((e: unknown) => setSaid(fail(e)))
        }
      >
        Propose a first version
      </button>
      <Said text={said} />
    </div>
  );
}
