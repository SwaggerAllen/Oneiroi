import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api } from '../../api/client';
import type { CheckinPart, ScheduleCheckin, ScheduleToday } from '../../api/types';
import { ScrollArea } from '../shell/ScrollArea';
import { useSubject } from '../state/resident';
import { allZones, canAddSlot, deviceZone, isHours, isTime, isWindow, moveSlot, SLOTS } from './rules';
import * as css from './time.css';

/**
 * Rhythm: the rules the calendar's events come from, edited in one place
 * (ui-structures.md D), ported from the current client's Schedule. Every
 * time is HH:MM where she lives. The witness may move her free time and
 * add to it, never take a slot away (the free-time term,
 * scheduling-notes.md); a slot is changed by moving it.
 */
export function Rhythm() {
  const { id, name } = useSubject();
  const queries = useQueryClient();
  const schedule = useQuery({ queryKey: ['resident', id, 'time', 'schedule'], queryFn: () => api.schedule(id) });
  const refresh = () => queries.invalidateQueries({ queryKey: ['resident', id, 'time'] });
  const s = schedule.data;

  return (
    <ScrollArea label="Rhythm">
      <div className={css.page}>
        {schedule.isPending && <p className={css.note}>Reading…</p>}
        {s && (
          <>
            <p className={css.note}>
              Every time here is {name}'s, in {s.timezone}.
            </p>
            <Checkins s={s} refresh={refresh} />
            <FreeTime s={s} refresh={refresh} />
            {s.rounds && <Rounds rounds={s.rounds} refresh={refresh} />}
            <Quiet quiet={s.quiet} refresh={refresh} />
            <Zone timezone={s.timezone} refresh={refresh} />
          </>
        )}
      </div>
    </ScrollArea>
  );
}

type Refresh = () => Promise<unknown>;

/** A write and what came of it: the button's state and the line under it. */
function useWrite<T>(fn: (v: T) => Promise<unknown>, refresh: Refresh) {
  return useMutation({ mutationFn: fn, onSuccess: () => refresh() });
}

function Failed({ error }: { error: Error | null }) {
  return error ? <p className={css.note}>That didn't go through: {error.message}</p> : null;
}

function Checkins({ s, refresh }: { s: ScheduleToday; refresh: Refresh }) {
  const { id } = useSubject();
  const [label, setLabel] = useState('');
  const [time, setTime] = useState('');
  const add = useWrite(() => api.addCheckin(id, label.trim(), time), refresh);
  const fired = new Map(s.firings.map((f) => [f.key, f.outcome]));
  return (
    <section className={css.section} aria-label="Check-ins">
      <h2 className={css.headingWitness}>CHECK-INS</h2>
      <p className={css.note}>{s.next ? `Next: ${s.next.label} at ${s.next.time}${s.next.tomorrow ? ' tomorrow' : ''}.` : 'None set.'}</p>
      {s.checkins.map((c) => (
        <Checkin key={c.key} c={c} today={fired.get(c.key) ?? null} catalog={s.checkin_parts ?? []} refresh={refresh} />
      ))}
      <form
        className={css.addRow}
        aria-label="Add a check-in"
        onSubmit={(e) => {
          e.preventDefault();
          add.mutate(undefined, {
            onSuccess: () => {
              setLabel('');
              setTime('');
            },
          });
        }}
      >
        <input className={css.time} value={label} maxLength={60} onChange={(e) => setLabel(e.target.value)} placeholder="Label" aria-label="Label" />
        <input type="time" className={css.time} value={time} onChange={(e) => setTime(e.target.value)} aria-label="Time" />
        <button type="submit" className={css.addButton} disabled={!label.trim() || !isTime(time) || add.isPending}>
          Add a check-in
        </button>
      </form>
      <Failed error={add.error} />
    </section>
  );
}

function Checkin({ c, today, catalog, refresh }: { c: ScheduleCheckin; today: string | null; catalog: CheckinPart[]; refresh: Refresh }) {
  const { id, name } = useSubject();
  const [editing, setEditing] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [label, setLabel] = useState(c.label);
  const [time, setTime] = useState(c.time);
  const [prompt, setPrompt] = useState(c.prompt ?? '');
  const [parts, setParts] = useState<string[]>(c.parts ?? ['dates']);
  const save = useWrite(
    () =>
      api.changeCheckin(id, c.key, label.trim(), time, {
        parts: catalog.map((p) => p.key).filter((k) => parts.includes(k)),
        prompt,
      }),
    refresh,
  );
  const remove = useWrite(() => api.deleteCheckin(id, c.key), refresh);
  const carries = catalog.filter((p) => (c.parts ?? ['dates']).includes(p.key)).map((p) => p.label);
  if (c.prompt) carries.unshift('your words');

  return (
    <div className={css.card}>
      <div className={css.cardHead}>
        <span>
          {c.label}
          <span className={css.meta}> · {today ? `TODAY: ${today.toUpperCase()}` : c.last_day ? `LAST ${(c.last_outcome ?? '').toUpperCase()} ${c.last_day}` : 'NOT RUN YET'}</span>
        </span>
        <span className={css.meta}>{c.time}</span>
      </div>
      <p className={css.note}>Carries: {carries.length > 0 ? carries.join(', ') : 'only the check-in line'}.</p>
      {editing ? (
        <form
          className={css.form}
          aria-label={`Change ${c.label}`}
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate(undefined, { onSuccess: () => setEditing(false) });
          }}
        >
          <div className={css.addRow}>
            <input className={css.time} value={label} maxLength={60} onChange={(e) => setLabel(e.target.value)} aria-label="Label" />
            <input type="time" className={css.time} value={time} onChange={(e) => setTime(e.target.value)} aria-label="Time" />
          </div>
          <textarea
            className={css.text}
            rows={3}
            maxLength={4000}
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder={`Anything you want ${name} to start from at this check-in`}
            aria-label="Your words"
          />
          <fieldset className={css.fieldset}>
            <legend className={css.meta}>PARTS, READ WHEN IT FIRES</legend>
            {catalog.map((p) => (
              <label key={p.key} className={css.check}>
                <input type="checkbox" checked={parts.includes(p.key)} onChange={() => setParts((x) => (x.includes(p.key) ? x.filter((k) => k !== p.key) : [...x, p.key]))} />
                <span>
                  {p.label}
                  <span className={css.note}> — {p.about}</span>
                </span>
              </label>
            ))}
          </fieldset>
          <div className={css.addRow}>
            <button type="submit" className={css.addButton} disabled={!label.trim() || !isTime(time) || save.isPending}>
              Save
            </button>
            <button type="button" className={css.quiet} onClick={() => setEditing(false)}>
              Cancel
            </button>
          </div>
          <Failed error={save.error} />
        </form>
      ) : (
        <div className={css.addRow}>
          <button type="button" className={css.quiet} onClick={() => setEditing(true)}>
            Change
          </button>
          {/* A removal confirms once, in place: the button becomes its consequence (screens/schedule.md). */}
          <button type="button" className={css.quiet} disabled={remove.isPending} onClick={() => (confirming ? remove.mutate(undefined) : setConfirming(true))} onBlur={() => setConfirming(false)}>
            {confirming ? `Delete ${c.label}` : 'Delete'}
          </button>
        </div>
      )}
      <Failed error={remove.error} />
    </div>
  );
}

function FreeTime({ s, refresh }: { s: ScheduleToday; refresh: Refresh }) {
  const { id, name } = useSubject();
  const times = s.free_times.map((f) => f.time);
  const set = useWrite((next: string[]) => api.setFreeTime(id, next), refresh);
  const once = useWrite(({ time, day }: { time: string; day: string | null }) => api.addFreeTimeOnce(id, time, day), refresh);
  const [adding, setAdding] = useState('');
  const [onceTime, setOnceTime] = useState('');
  const [onceDay, setOnceDay] = useState('');
  return (
    <section className={css.section} aria-label="Free time">
      <h2 className={css.headingHers}>FREE TIME · HERS</h2>
      {s.free_times.map((f) => (
        <label key={f.time} className={css.rowHers}>
          <span>
            Daily
            <span className={css.meta}> · {f.today === null ? 'NOT YET TODAY' : f.today === 'ran' ? 'RAN TODAY' : `TODAY: ${f.today.toUpperCase()}`}</span>
          </span>
          <input
            type="time"
            className={css.time}
            defaultValue={f.time}
            aria-label={`Move the ${f.time} slot`}
            onBlur={(e) => isTime(e.target.value) && e.target.value !== f.time && !times.includes(e.target.value) && set.mutate(moveSlot(times, f.time, e.target.value))}
          />
        </label>
      ))}
      {times.length < SLOTS ? (
        <div className={css.addRow}>
          <input type="time" className={css.time} value={adding} onChange={(e) => setAdding(e.target.value)} aria-label="A new daily free-time slot" />
          <button
            type="button"
            className={css.addButton}
            disabled={!canAddSlot(times, adding) || set.isPending}
            onClick={() => set.mutate([...times, adding], { onSuccess: () => setAdding('') })}
          >
            Add a slot
          </button>
        </div>
      ) : (
        <p className={css.note}>Four slots a day is the most there can be.</p>
      )}
      <Failed error={set.error} />
      <p className={css.note}>Slots move; they never disappear. Only {name} can take one away.</p>
      <h2 className={css.headingHers}>ONCE</h2>
      {(s.free_time_once ?? []).length === 0 && <p className={css.note}>None ahead.</p>}
      {(s.free_time_once ?? []).map((o) => (
        <div key={`${o.day}-${o.time}`} className={css.rowHers}>
          <span>
            Once
            <span className={css.meta}> · ADDED BY {o.added_by === 'witness' ? 'YOU' : name.toUpperCase()}</span>
          </span>
          <span className={css.meta}>
            {o.day} {o.time}
          </span>
        </div>
      ))}
      <div className={css.addRow}>
        <input type="time" className={css.time} value={onceTime} onChange={(e) => setOnceTime(e.target.value)} aria-label="One-off free time at" />
        <input type="date" className={css.time} value={onceDay} onChange={(e) => setOnceDay(e.target.value)} aria-label="On (empty is today)" />
        <button
          type="button"
          className={css.addButton}
          disabled={!isTime(onceTime) || once.isPending}
          onClick={() =>
            once.mutate(
              { time: onceTime, day: onceDay || null },
              {
                onSuccess: () => {
                  setOnceTime('');
                  setOnceDay('');
                },
              },
            )
          }
        >
          Add once
        </button>
      </div>
      <Failed error={once.error} />
    </section>
  );
}

function Rounds({ rounds, refresh }: { rounds: NonNullable<ScheduleToday['rounds']>; refresh: Refresh }) {
  const { id, name } = useSubject();
  const [every, setEvery] = useState(String(rounds.every_hours));
  const [waking, setWaking] = useState(rounds.waking ?? '');
  const set = useWrite(({ e, w }: { e: number | null; w: string | null }) => api.setRounds(id, e, w), refresh);
  const on = rounds.every_hours > 0;
  const windowOk = rounds.waking_from_quiet || waking.trim() === '' || isWindow(waking.trim());
  return (
    <section className={css.section} aria-label="Rounds">
      <h2 className={css.heading}>ROUNDS</h2>
      <p className={css.note}>
        {on
          ? `${name} has a round every ${rounds.every_hours} hours${rounds.every_default ? ' (the default)' : ''}, at a time drawn at random ${
              rounds.waking_from_quiet ? 'outside quiet hours' : `between ${rounds.waking?.replace('-', ' and ')}`
            }: ${rounds.today} today.`
          : `Off: ${name} has no rounds.`}{' '}
        {rounds.last_at ? `The last started ${new Date(rounds.last_at).toLocaleString()}.` : 'None has started yet.'} What happens in a round stays hers.
      </p>
      <form
        className={css.addRow}
        aria-label="Set rounds"
        onSubmit={(e) => {
          e.preventDefault();
          set.mutate({ e: Number(every), w: rounds.waking_from_quiet ? null : waking.trim() || null });
        }}
      >
        <input className={css.time} inputMode="numeric" value={every} onChange={(e) => setEvery(e.target.value)} aria-label="Every (hours, 0 is off)" size={4} />
        {!rounds.waking_from_quiet && <input className={css.time} value={waking} onChange={(e) => setWaking(e.target.value)} placeholder="08:00-22:00" aria-label="Between (HH:MM-HH:MM)" />}
        <button type="submit" className={css.addButton} disabled={!isHours(every) || !windowOk || set.isPending}>
          Set rounds
        </button>
        {!(rounds.every_default && rounds.waking_default) && (
          <button type="button" className={css.quiet} onClick={() => set.mutate({ e: null, w: null })}>
            Back to the default
          </button>
        )}
      </form>
      <Failed error={set.error} />
    </section>
  );
}

function Quiet({ quiet, refresh }: { quiet: ScheduleToday['quiet']; refresh: Refresh }) {
  const { id } = useSubject();
  const [from, setFrom] = useState(quiet?.from ?? '');
  const [to, setTo] = useState(quiet?.to ?? '');
  const set = useWrite(({ f, t }: { f: string | null; t: string | null }) => api.setQuietHours(id, f, t), refresh);
  return (
    <section className={css.section} aria-label="Quiet hours">
      <h2 className={css.heading}>QUIET HOURS</h2>
      <p className={css.note}>{quiet ? `${quiet.from} to ${quiet.to}: check-ins wait until they end. Free time doesn't.` : 'None: a check-in fires at its time.'}</p>
      <form
        className={css.addRow}
        aria-label="Set quiet hours"
        onSubmit={(e) => {
          e.preventDefault();
          set.mutate({ f: from, t: to });
        }}
      >
        <input type="time" className={css.time} value={from} onChange={(e) => setFrom(e.target.value)} aria-label="From" />
        <input type="time" className={css.time} value={to} onChange={(e) => setTo(e.target.value)} aria-label="To" />
        <button type="submit" className={css.addButton} disabled={!isTime(from) || !isTime(to) || set.isPending}>
          Set quiet hours
        </button>
        {quiet && (
          <button type="button" className={css.quiet} onClick={() => set.mutate({ f: null, t: null })}>
            Clear
          </button>
        )}
      </form>
      <Failed error={set.error} />
    </section>
  );
}

function Zone({ timezone, refresh }: { timezone: string; refresh: Refresh }) {
  const { id } = useSubject();
  const device = deviceZone();
  const [chosen, setChosen] = useState(timezone);
  const set = useWrite((tz: string) => api.setTimezone(id, tz), refresh);
  return (
    <section className={css.section} aria-label="Time zone">
      <h2 className={css.heading}>TIME ZONE</h2>
      <p className={css.note}>
        {timezone}
        {device && device !== timezone ? `. This device is in ${device}.` : '.'}
      </p>
      <div className={css.addRow}>
        <select className={css.time} value={chosen} onChange={(e) => setChosen(e.target.value)} aria-label="Zone">
          {allZones(timezone, device).map((z) => (
            <option key={z} value={z}>
              {z}
            </option>
          ))}
        </select>
        <button type="button" className={css.addButton} disabled={chosen === timezone || set.isPending} onClick={() => set.mutate(chosen)}>
          Set the zone
        </button>
        {device && device !== timezone && (
          <button type="button" className={css.quiet} onClick={() => set.mutate(device)}>
            Use {device}
          </button>
        )}
      </div>
      <Failed error={set.error} />
    </section>
  );
}
