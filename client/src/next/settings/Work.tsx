import { Linked } from '../shell/Linked';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type BackfillPass } from '../../api/client';
import type { WorkItem, WorkQueue } from '../../api/types';
import { useSubject } from '../state/resident';
import { Card, Field, Said, Select } from './common';
import * as css from './settings.css';
import { useAct } from './useAct';
import { useNow } from '../shell/presence';
import { blockedLine, isLive, LONG_RUN_SECONDS, loopLine, movedUp, runSeconds, settingsKey, timeLine } from './logic';

type Move = (n: number, status: string, blockedOn: string | null, note: string) => void;
type Hold = (n: number, ask: string) => void;

/**
 * The work queue (sunna#33, #38): her long items and yours in one list in
 * priority order, and the loop that runs the first open one, wraps it and
 * fires the next. Arm or turn off the line (sunna#43), reorder, move an
 * item's status with a note, hold one for your word with an ask and
 * release it (sunna#54, #55), and read each item's last wrap.
 */
export function Work() {
  const { id, name } = useSubject();
  const work = useQuery({
    queryKey: settingsKey(id, 'work'),
    queryFn: () => api.work(id),
  });
  const [what, setWhat] = useState('');
  const [doneWhen, setDoneWhen] = useState('');
  const [resetNote, setResetNote] = useState('');
  const [skipNote, setSkipNote] = useState('');
  const act = useAct();
  const run = (work: () => Promise<string>) => void act.run(work, ['resident', id, 'sessions'], ['resident', id, 'bell']);

  if (work.isPending) return <p className={css.note}>Reading…</p>;
  if (!work.data) return <p className={css.refused}>The queue could not be read.</p>;
  const q = work.data;
  const live = q.items.filter(isLive);
  const finished = q.items.filter((i) => !isLive(i)).slice(-5);
  const move: Move = (n, status, blockedOn, note) => run(() => api.moveWork(id, n, status, blockedOn, note).then(() => `#${n} is ${status === 'open' ? 'open again' : status}.`));
  const hold: Hold = (n, ask) => run(() => api.holdWork(id, n, ask, null).then(() => `#${n} is held for you; the loop steps over it until you release it.`));

  return (
    <>
      <Card title="The work line" witness>
        <LoopLine name={name} q={q} />
        {!q.armed && (q.house_queue || live.some((i) => i.status === 'open')) && (
          <div>
            <button type="button" className={css.primary} disabled={act.busy} onClick={() => run(() => api.armWork(id).then(() => 'Armed.'))}>
              Arm the work line
            </button>
          </div>
        )}
        {q.armed && (
          <div className={css.column}>
            <div>
              <button type="button" className={css.secondary} disabled={act.busy} onClick={() => run(() => api.disarmWork(id).then(() => 'The work line is off.'))}>
                Turn the work line off
              </button>
            </div>
            {q.running !== null && <span className={css.note}>The run in work finishes; nothing starts after it until the line is armed again.</span>}
          </div>
        )}
        {q.armed && q.running === null && (q.rested ?? '').startsWith('waiting: a free-time pass') && (
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
        {q.runs_today > 0 && (
          <div className={css.column}>
            <span className={css.note}>
              {q.runs_today} of {q.runs_a_day} runs used today.
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
                      return "Today's runs are back; the loop checks now.";
                    }),
                  )
                }
              >
                Reset today's runs
              </button>
            </div>
          </div>
        )}
        <Said said={act.said} />
      </Card>

      {q.house_queue ? (
        // At the cutover (lily:design/queue-ia §2.1) her items give way to
        // the house queue: the line above still runs it, and her work is
        // read in Work with her as the holder.
        <Card title="Her work">
          <p className={css.note}>Since the cutover {name}'s work is in the house queue, and this line runs it. Her items stay below, read-only.</p>
          <div>
            <a className={css.link} href="#/settings/queue">
              Open Work ›
            </a>
          </div>
        </Card>
      ) : null}
      <Card title={q.house_queue ? `Before the cutover · ${live.length}` : `In order · ${live.length}`}>
        {live.length === 0 && <p className={css.note}>Nothing open.</p>}
        <ol className={css.list} aria-label="Work items">
          {live.map((item, i) => (
            <Item
              key={item.number}
              item={item}
              items={q.items}
              q={q}
              busy={act.busy}
              onUp={
                i === 0
                  ? undefined
                  : () => {
                      const order = movedUp(q.items, item.number);
                      if (order) run(() => api.orderWork(id, order).then(() => `#${item.number} moved up.`));
                    }
              }
              onMove={move}
              onHold={hold}
            />
          ))}
        </ol>
      </Card>

      {!q.house_queue && (
        <Card title="Add work">
          <form
            aria-label="Add work"
            className={css.column}
            onSubmit={(e) => {
              e.preventDefault();
              const w = what.trim();
              const d = doneWhen.trim();
              if (!w || !d) return;
              setWhat('');
              setDoneWhen('');
              run(() => api.addWork(id, w, d).then((r) => `Added as #${r.number}.`));
            }}
          >
            <Field label="What (one line)" value={what} onChange={(e) => setWhat(e.target.value)} />
            <Field label="Done when" value={doneWhen} onChange={(e) => setDoneWhen(e.target.value)} />
            <div>
              <button type="submit" className={css.primary} disabled={what.trim() === '' || doneWhen.trim() === '' || act.busy}>
                Add to the queue
              </button>
            </div>
          </form>
        </Card>
      )}

      {finished.length > 0 && (
        <Card title="Lately finished">
          <ul className={css.list} aria-label="Finished work">
            {finished.map((i) => (
              <li key={i.number} className={css.item}>
                <span className={css.text}>
                  #{i.number} {i.what}: {i.status}
                </span>
                {i.shipped && <span className={css.note}>Shipped: {i.shipped}</span>}
              </li>
            ))}
          </ul>
        </Card>
      )}
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

// The loop's line, ticking while an item runs so its time stays true.
function LoopLine({ name, q }: { name: string; q: WorkQueue }) {
  const now = useNow(q.running !== null);
  return <p className={css.text}>{loopLine(name, q, now)}</p>;
}

/**
 * How long an item has been in work (sunna#58), ticking while it runs;
 * a run past an hour is marked for a look, the line the witness reads to
 * judge whether it wants review.
 */
function TimeLine({ item, q }: { item: WorkItem; q: WorkQueue }) {
  const now = useNow(q.running === item.number);
  const run = runSeconds(q, item.number, now);
  const long = run !== null && run >= LONG_RUN_SECONDS;
  return (
    <span className={long ? `${css.note} ${css.warn}` : css.note}>
      {timeLine(item, q, now)}
      {long ? ' · running long: worth a look' : ''}
    </span>
  );
}

function Item({ item, items, q, busy, onUp, onMove, onHold }: { item: WorkItem; items: WorkItem[]; q: WorkQueue; busy: boolean; onUp?: () => void; onMove: Move; onHold: Hold }) {
  const [note, setNote] = useState('');
  const [blockedOn, setBlockedOn] = useState('');
  const [holding, setHolding] = useState(false);
  const [ask, setAsk] = useState('');
  const held = item.status === 'held';
  // What it can wait on: another item still to be done.
  const blockers = items.filter((i) => i.number !== item.number && isLive(i));
  const noted = note.trim() !== '' && !busy;
  const move = (status: string) => {
    onMove(item.number, status, status === 'blocked' ? blockedOn : null, note.trim());
    setNote('');
  };
  return (
    <li className={css.item}>
      <strong className={css.text}>
        #{item.number} {item.what}
      </strong>
      <span className={css.note}>
        {item.status === 'blocked' ? blockedLine(item.blocked_on, items) : item.status === 'in_work' ? 'running now' : held ? 'held for you' : 'open'} · added by{' '}
        {item.added_by === 'witness' ? 'you' : 'her'}
      </span>
      {item.runs > 0 && <TimeLine item={item} q={q} />}
      <span className={css.note}>Done when: {item.done_when}</span>
      {item.wrapped_at && (
        <span className={css.note}>
          Last wrap: shipped {item.shipped}
          {item.slipped ? `; slipped ${item.slipped}` : ''}; why: {item.why}
        </span>
      )}
      {held && (
        <span className={css.text}>
          HELD · {item.held_by === 'witness' ? 'you held it' : 'she asks you'}: <Linked text={item.held_ask ?? ''} />
        </span>
      )}
      {item.note && <span className={css.note}>Note: {item.note}</span>}
      {holding && !held && (
        <div className={css.row}>
          <Field label={`What #${item.number} waits on you for`} value={ask} onChange={(e) => setAsk(e.target.value)} />
          <button
            type="button"
            className={css.quiet}
            disabled={busy || ask.trim() === ''}
            onClick={() => {
              onHold(item.number, ask.trim());
              setAsk('');
              setHolding(false);
            }}
          >
            Hold
          </button>
        </div>
      )}
      <div className={css.row}>
        <Field label={`A note on #${item.number}`} value={note} onChange={(e) => setNote(e.target.value)} />
        {blockers.length > 0 && (
          <>
            <Select label="Blocked on" value={blockedOn} onChange={setBlockedOn}>
              <option value="">another item…</option>
              {blockers.map((b) => (
                <option key={b.number} value={String(b.number)}>
                  #{b.number} {b.what}
                </option>
              ))}
            </Select>
            <button type="button" className={css.quiet} disabled={!noted || blockedOn === ''} onClick={() => move('blocked')}>
              Blocked
            </button>
          </>
        )}
        {item.status === 'blocked' && (
          <button type="button" className={css.quiet} disabled={!noted} onClick={() => move('open')}>
            Unblock
          </button>
        )}
        {held ? (
          <button type="button" className={css.quiet} disabled={!noted} onClick={() => move('open')}>
            Release
          </button>
        ) : (
          <button type="button" className={css.quiet} disabled={busy} aria-expanded={holding} onClick={() => setHolding((h) => !h)}>
            Hold for me…
          </button>
        )}
        <button type="button" className={css.quiet} disabled={!noted} onClick={() => move('done')}>
          Done
        </button>
        <button type="button" className={css.quiet} disabled={!noted} onClick={() => move('dropped')}>
          Drop
        </button>
        {onUp && (
          <button type="button" className={css.quiet} disabled={busy} onClick={onUp}>
            Move up
          </button>
        )}
      </div>
    </li>
  );
}
