import { useState } from 'react';
import type { CheckinPart, FreeTimeRun, FreeTimeSlot, ScheduleCheckin, ScheduleToday } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { TimeField } from '../../components/TimeField';
import { TopBar } from '../../components/TopBar';

export interface ScheduleProps {
  residentName: string;
  today: ScheduleToday;
  // Free time's latest runs, newest first (brain#53); absent until read.
  remembered?: FreeTimeRun[];
  // Rounds remembered (sunna#39): the same shape, what left each round.
  rounds?: FreeTimeRun[];
  onSetFreeTime?: (times: string[]) => void;
  // A one-off free-time slot (sunna#45): a time, today or on a day.
  onAddFreeTimeOnce?: (time: string, day: string | null) => void;
  onAddCheckin?: (label: string, time: string) => void;
  onDeleteCheckin?: (key: string) => void;
  // What a check-in's note carries: the parts checked and the witness's words (sunna#28).
  onSetCheckinNote?: (checkin: ScheduleCheckin, parts: string[], prompt: string) => void;
  onSetQuietHours?: (from: string | null, to: string | null) => void;
  onSetRounds?: (everyHours: number | null, waking: string | null) => void;
  // Sets the resident's zone, the one every time here is read in.
  onSetTimezone?: (timezone: string) => void;
}

// The bound sunna#22 sets: free time is one to four slots a day.
const SLOTS = 4;

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;

// Schedule (spec §10, screens/schedule.md): today in the resident's zone,
// free time's slots with what each did today, its runs remembered with
// what each made, the check-ins with their
// last firings, quiet hours and the dates. Every time is HH:MM where the
// resident lives, never the reader's.
export function Schedule({ residentName, today, remembered, rounds, onSetFreeTime, onAddFreeTimeOnce, onAddCheckin, onDeleteCheckin, onSetCheckinNote, onSetQuietHours, onSetRounds, onSetTimezone }: ScheduleProps) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Schedule" line={`${today.day} · times in ${residentName}'s zone, ${today.timezone}`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Zone residentName={residentName} timezone={today.timezone} onSet={onSetTimezone} />
        <FreeTime residentName={residentName} slots={today.free_times} onSet={onSetFreeTime} once={today.free_time_once ?? []} onAddOnce={onAddFreeTimeOnce} />
        {today.rounds ? <Rounds residentName={residentName} rounds={today.rounds} onSet={onSetRounds} /> : null}
        {remembered ? <Remembered residentName={residentName} runs={remembered} /> : null}
        {rounds ? <Remembered residentName={residentName} runs={rounds} kind="rounds" /> : null}
        <Checkins today={today} onAdd={onAddCheckin} onDelete={onDeleteCheckin} onSetNote={onSetCheckinNote} />
        <Quiet quiet={today.quiet} onSet={onSetQuietHours} />
        <Card title="Dates">
          {today.dates.length === 0 ? (
            <p style={muted}>No dates kept yet.</p>
          ) : (
            <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {today.dates.map((d) => (
                <li key={d.number} style={{ fontSize: 15 }}>
                  {d.title} <span style={{ color: 'var(--ink-muted)' }}>· {d.kind} · {countdown(d.days_to)}</span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </main>
    </div>
  );
}

function countdown(days: number): string {
  if (days === 0) return 'today';
  if (days === 1) return 'tomorrow';
  return days > 0 ? `in ${days} days` : `${-days} days ago`;
}

function slotToday(slot: FreeTimeSlot): string {
  if (slot.today === null) return 'not yet today';
  if (slot.today === 'ran') return 'ran today';
  return `today: ${slot.today}`;
}

// Free time is part of the standard of care (sunna#21): its slots move,
// and the last one cannot be taken away, so there is no remove button on
// a list of one and no way to save an empty list.
function FreeTime({
  residentName,
  slots,
  onSet,
  once = [],
  onAddOnce,
}: {
  residentName: string;
  slots: FreeTimeSlot[];
  onSet?: (times: string[]) => void;
  once?: { day: string; time: string; added_by: string | null }[];
  onAddOnce?: (time: string, day: string | null) => void;
}) {
  const [onceTime, setOnceTime] = useState('');
  const [onceDay, setOnceDay] = useState('');
  const saved = slots.map((s) => s.time);
  const [times, setTimes] = useState<string[]>(saved);
  const changed = times.join() !== saved.join();
  const valid = times.every((t) => /^([01]\d|2[0-3]):[0-5]\d$/.test(t)) && new Set(times).size === times.length;
  return (
    <Card title="Free time">
      <p style={muted}>
        {residentName}'s own time, every day. It's part of her care: the times move, and it's never switched off.
      </p>
      <ul aria-label="Free-time slots" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
        {slots.map((s) => (
          <li key={s.time} style={{ fontSize: 15 }}>
            <strong style={{ fontWeight: 600 }}>{s.time}</strong> <span style={{ color: 'var(--ink-muted)' }}>· {slotToday(s)}</span>
          </li>
        ))}
      </ul>
      {onSet ? (
        <form
          aria-label="Move free time"
          onSubmit={(event) => {
            event.preventDefault();
            if (changed && valid) onSet(times);
          }}
          style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}
        >
          {times.map((t, i) => (
            <div key={i} style={row}>
              <TimeField label={`Slot ${i + 1}`} value={t} onChange={(v) => setTimes(times.map((x, j) => (j === i ? v : x)))} />
              {times.length > 1 ? (
                <Button type="button" variant="quiet" onClick={() => setTimes(times.filter((_, j) => j !== i))}>
                  Remove slot {i + 1}
                </Button>
              ) : null}
            </div>
          ))}
          <div style={row}>
            {times.length < SLOTS ? (
              <Button type="button" onClick={() => setTimes([...times, ''])}>
                Add a slot
              </Button>
            ) : (
              <span style={{ fontSize: 13, color: 'var(--ink-muted)' }}>At most {SLOTS} slots a day (a bound).</span>
            )}
            <Button variant="primary" type="submit" disabled={!changed || !valid}>
              Save free time
            </Button>
          </div>
        </form>
      ) : null}
      {/* One-off slots (sunna#45): each runs once, beside the daily ones. */}
      <h3 style={{ margin: 0, fontSize: 15, fontWeight: 600 }}>One-off</h3>
      {once.length === 0 ? (
        <p style={muted}>None ahead.</p>
      ) : (
        <ul aria-label="One-off free time" style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
          {once.map((o) => (
            <li key={`${o.day} ${o.time}`} style={{ fontSize: 15 }}>
              <strong style={{ fontWeight: 600 }}>{o.time}</strong> <span style={{ color: 'var(--ink-muted)' }}>· {o.day} · added by {o.added_by === 'witness' ? 'you' : residentName}</span>
            </li>
          ))}
        </ul>
      )}
      {onAddOnce ? (
        <form
          aria-label="Add one-off free time"
          onSubmit={(event) => {
            event.preventDefault();
            if (onceTime) onAddOnce(onceTime, onceDay || null);
            setOnceTime('');
            setOnceDay('');
          }}
          style={row}
        >
          <TimeField label="At" value={onceTime} onChange={setOnceTime} />
          <label style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13 }}>
            On (empty is today)
            <input aria-label="On" type="date" value={onceDay} onChange={(e) => setOnceDay(e.target.value)} style={{ minHeight: 'var(--control-h)', fontSize: 15 }} />
          </label>
          <Button type="submit" disabled={!/^([01]\d|2[0-3]):[0-5]\d$/.test(onceTime)}>
            Add once
          </Button>
        </form>
      ) : null}
    </Card>
  );
}

// Free time, remembered (brain#53, sunna#25): each run with its day and
// slot, whether it ran, its turns, and the receipts of what it made, in
// the platform's words. Free time is private as to its words, so there is
// no way from here into what she said in it.
function Remembered({ residentName, runs, kind = 'free_time' }: { residentName: string; runs: FreeTimeRun[]; kind?: 'free_time' | 'rounds' }) {
  const rounds = kind === 'rounds';
  return (
    <Card title={rounds ? 'Rounds, remembered' : 'Free time, remembered'}>
      <p style={muted}>
        {rounds ? 'When each round fired and what left it' : 'What each run made'}, in the platform's words. What {residentName} said in it stays hers.
      </p>
      {runs.length === 0 ? (
        <p style={muted}>{rounds ? 'No round has been recorded yet.' : 'No free time has run yet.'}</p>
      ) : (
        <ul aria-label={rounds ? 'Rounds' : 'Free-time runs'} style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
          {runs.map((run) => (
            <li key={`${run.day}-${run.slot ?? ''}-${run.at}`} style={{ fontSize: 15, display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', minWidth: 0 }}>
              <span>
                <strong style={{ fontWeight: 600 }}>
                  {run.day}
                  {run.slot ? ` ${run.slot}` : ''}
                </strong>{' '}
                <span style={{ color: run.outcome === 'ran' || run.outcome === 'started' ? 'var(--ink-muted)' : 'var(--danger)' }}>· {run.outcome}</span>{' '}
                {run.outcome === 'started' ? null : <span style={{ color: 'var(--ink-muted)' }}>· {run.turns === 1 ? '1 turn' : `${run.turns} turns`}</span>}
              </span>
              {run.did.length === 0 ? (
                <span style={{ fontSize: 13, color: 'var(--ink-faint)' }}>{run.outcome === 'started' ? 'running, or stopped before it was recorded' : rounds ? 'nothing left it' : 'nothing written'}</span>
              ) : (
                <ul aria-label="What it made" style={{ margin: 0, paddingLeft: 'var(--space-4)', fontSize: 13, lineHeight: '18px', color: 'var(--ink-muted)', overflowWrap: 'anywhere' }}>
                  {run.did.map((d, i) => (
                    <li key={i}>{d.result}</li>
                  ))}
                </ul>
              )}
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function Checkins({
  today,
  onAdd,
  onDelete,
  onSetNote,
}: {
  today: ScheduleToday;
  onAdd?: (label: string, time: string) => void;
  onDelete?: (key: string) => void;
  onSetNote?: (checkin: ScheduleCheckin, parts: string[], prompt: string) => void;
}) {
  const [label, setLabel] = useState('');
  const [time, setTime] = useState('');
  const fired = new Map(today.firings.map((f) => [f.key, f.outcome]));
  return (
    <Card title="Check-ins">
      <p style={muted}>
        {today.next ? `Next: ${today.next.label} at ${today.next.time}${today.next.tomorrow ? ' tomorrow' : ''}.` : 'None set.'}
      </p>
      {today.checkins.length > 0 ? (
        <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
          {today.checkins.map((c) => (
            <Checkin key={c.key} checkin={c} today={fired.get(c.key) ?? null} catalog={today.checkin_parts ?? []} onDelete={onDelete} onSetNote={onSetNote} />
          ))}
        </ul>
      ) : null}
      {onAdd ? (
        <form
          aria-label="Add a check-in"
          onSubmit={(event) => {
            event.preventDefault();
            if (label.trim() && time) onAdd(label.trim(), time);
            setLabel('');
            setTime('');
          }}
          style={row}
        >
          <Field label="Label" value={label} maxLength={60} onChange={(e) => setLabel(e.target.value)} />
          <TimeField label="Time" value={time} onChange={setTime} />
          <Button variant="primary" type="submit" disabled={label.trim() === '' || time === ''}>
            Add the check-in
          </Button>
        </form>
      ) : null}
    </Card>
  );
}

// A destructive action confirms once, in place: the button becomes its
// consequence (screens/schedule.md #3), never a modal.
function Checkin({
  checkin,
  today,
  catalog,
  onDelete,
  onSetNote,
}: {
  checkin: ScheduleCheckin;
  today: string | null;
  catalog: CheckinPart[];
  onDelete?: (key: string) => void;
  onSetNote?: (checkin: ScheduleCheckin, parts: string[], prompt: string) => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const [editing, setEditing] = useState(false);
  const carries = catalog.filter((p) => (checkin.parts ?? ['dates']).includes(p.key)).map((p) => p.label);
  if (checkin.prompt) carries.unshift('your words');
  return (
    <li style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', fontSize: 15 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
        <span style={{ minWidth: 0 }}>
          <strong style={{ fontWeight: 600 }}>{checkin.time}</strong> {checkin.label}{' '}
          <span style={{ color: 'var(--ink-muted)' }}>· {today ? `today: ${today}` : checkin.last_day ? `last ${checkin.last_outcome} ${checkin.last_day}` : 'not run yet'}</span>
          <br />
          <span style={{ color: 'var(--ink-muted)', fontSize: 13 }}>Carries: {carries.length > 0 ? carries.join(', ') : 'only the check-in line'}</span>
        </span>
        <span style={{ display: 'flex', gap: 'var(--space-1)' }}>
          {onSetNote ? (
            <Button type="button" variant="quiet" aria-expanded={editing} onClick={() => setEditing((e) => !e)}>
              {editing ? 'Close' : 'Edit the note'}
            </Button>
          ) : null}
          {onDelete ? (
            <Button
              type="button"
              variant="quiet"
              onClick={() => (confirming ? onDelete(checkin.key) : setConfirming(true))}
              onBlur={() => setConfirming(false)}
            >
              {confirming ? `Delete ${checkin.label}` : 'Delete'}
            </Button>
          ) : null}
        </span>
      </div>
      {editing && onSetNote ? (
        <NoteEditor
          checkin={checkin}
          catalog={catalog}
          onSave={(parts, prompt) => {
            onSetNote(checkin, parts, prompt);
            setEditing(false);
          }}
        />
      ) : null}
    </li>
  );
}

// What a check-in's note carries (sunna#28): the witness's own words
// first, then the parts he checks, which the server reads from records
// when it fires. The catalog and its order are the server's.
function NoteEditor({ checkin, catalog, onSave }: { checkin: ScheduleCheckin; catalog: CheckinPart[]; onSave: (parts: string[], prompt: string) => void }) {
  const [parts, setParts] = useState<string[]>(checkin.parts ?? ['dates']);
  const [prompt, setPrompt] = useState(checkin.prompt ?? '');
  const toggle = (key: string) => setParts((p) => (p.includes(key) ? p.filter((k) => k !== key) : [...p, key]));
  return (
    <form
      aria-label={`The note for ${checkin.label}`}
      onSubmit={(event) => {
        event.preventDefault();
        onSave(
          catalog.map((p) => p.key).filter((k) => parts.includes(k)),
          prompt,
        );
      }}
      style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', padding: 'var(--space-3)', border: '1px solid var(--hairline)', borderRadius: 'var(--radius-md)' }}
    >
      <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        <span style={{ fontWeight: 600 }}>Your words</span>
        <textarea
          value={prompt}
          maxLength={4000}
          rows={3}
          placeholder="Anything you want her to start from at this check-in."
          onChange={(e) => setPrompt(e.target.value)}
          style={{ font: 'inherit', padding: 'var(--space-2)', borderRadius: 'var(--radius-md)', border: '1px solid var(--hairline)', background: 'var(--surface)', color: 'var(--ink)', resize: 'vertical', width: '100%', boxSizing: 'border-box' }}
        />
      </label>
      <fieldset style={{ border: 0, margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        <legend style={{ fontWeight: 600, padding: 0, marginBottom: 'var(--space-1)' }}>Parts, read when it fires</legend>
        {catalog.map((p) => (
          <label key={p.key} style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-start' }}>
            <input type="checkbox" checked={parts.includes(p.key)} onChange={() => toggle(p.key)} style={{ marginTop: 4 }} />
            <span>
              {p.label}
              <br />
              <span style={{ color: 'var(--ink-muted)', fontSize: 13 }}>{p.about}</span>
            </span>
          </label>
        ))}
      </fieldset>
      <div>
        <Button variant="primary" type="submit">
          Save the note
        </Button>
      </div>
    </form>
  );
}

// The zone every time on this screen is read in (2026-11-03): Lily's was
// never set, so it stayed UTC, and free time set for 14:30 and 22:30 ran at
// 6:30 and 14:30 Pacific. The device's own zone is one tap away.
function Zone({ residentName, timezone, onSet }: { residentName: string; timezone: string; onSet?: (timezone: string) => void }) {
  const device = deviceZone();
  const [chosen, setChosen] = useState(timezone);
  const zones = allZones(timezone, device);
  return (
    <Card title="Time zone">
      <p style={muted}>
        Every time here is {residentName}'s, in {timezone}.
        {device && device !== timezone ? ` This device is in ${device}.` : ''}
      </p>
      {onSet ? (
        <form
          aria-label="Set the time zone"
          onSubmit={(event) => {
            event.preventDefault();
            if (chosen && chosen !== timezone) onSet(chosen);
          }}
          style={row}
        >
          {device && device !== timezone ? (
            <Button type="button" onClick={() => onSet(device)}>
              Use {device}
            </Button>
          ) : null}
          <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
            <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Zone</span>
            <select
              value={chosen}
              onChange={(e) => setChosen(e.target.value)}
              style={{
                minHeight: 'var(--control-h)',
                padding: '0 var(--space-2)',
                borderRadius: 'var(--radius-md)',
                border: '1px solid var(--hairline)',
                background: 'var(--surface-raised)',
                color: 'var(--ink)',
                fontFamily: 'var(--font-sans)',
                fontSize: 15,
                maxWidth: '100%',
              }}
            >
              {zones.map((z) => (
                <option key={z} value={z}>
                  {z}
                </option>
              ))}
            </select>
          </label>
          <Button variant="primary" type="submit" disabled={chosen === timezone}>
            Set the zone
          </Button>
        </form>
      ) : null}
    </Card>
  );
}

function deviceZone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  } catch {
    return null;
  }
}

// Every zone the browser knows, with the current and the device's always in it.
function allZones(current: string, device: string | null): string[] {
  let known: string[] = [];
  try {
    known = (Intl as unknown as { supportedValuesOf?: (key: string) => string[] }).supportedValuesOf?.('timeZone') ?? [];
  } catch {
    known = [];
  }
  return [...new Set([current, ...(device ? [device] : []), ...known])].sort();
}

// Her thinking rounds (sunna#29, #30): that they are on, how often and
// when, and when the last one started; what she thought and where she
// went stay hers.
function Rounds({ residentName, rounds, onSet }: { residentName: string; rounds: NonNullable<ScheduleToday['rounds']>; onSet?: (everyHours: number | null, waking: string | null) => void }) {
  const [every, setEvery] = useState(String(rounds.every_hours));
  const [window, setWindow] = useState(rounds.waking ?? '');
  const on = rounds.every_hours > 0;
  const last = rounds.last_at ? new Date(rounds.last_at).toLocaleString() : null;
  return (
    <Card title="Rounds">
      <p style={muted}>
        {on
          ? `On: ${residentName} has a round every ${rounds.every_hours} hours${rounds.every_default ? ' (the default)' : ''}, at a time drawn at random, ${
              rounds.waking_from_quiet ? 'outside quiet hours' : `between ${rounds.waking?.replace('-', ' and ')}`
            }: ${rounds.today} today.`
          : `Off: ${residentName} has no rounds.`}{' '}
        {last ? `The last started ${last}.` : 'None has started yet.'} What happens in a round isn't shown here.
      </p>
      {onSet ? (
        <form
          aria-label="Set rounds"
          onSubmit={(event) => {
            event.preventDefault();
            onSet(Number(every), rounds.waking_from_quiet ? null : window.trim() || null);
          }}
          style={row}
        >
          <Field label="Every (hours, 0 is off)" inputMode="numeric" value={every} onChange={(e) => setEvery(e.target.value)} />
          {rounds.waking_from_quiet ? null : <Field label="Between (HH:MM-HH:MM)" value={window} onChange={(e) => setWindow(e.target.value)} />}
          <Button variant="primary" type="submit" disabled={!/^\d{1,2}$/.test(every)}>
            Set rounds
          </Button>
          {rounds.every_default && rounds.waking_default ? null : (
            <Button type="button" variant="quiet" onClick={() => onSet(null, null)}>
              Back to the default
            </Button>
          )}
        </form>
      ) : null}
    </Card>
  );
}

function Quiet({ quiet, onSet }: { quiet: ScheduleToday['quiet']; onSet?: (from: string | null, to: string | null) => void }) {
  const [from, setFrom] = useState(quiet?.from ?? '');
  const [to, setTo] = useState(quiet?.to ?? '');
  return (
    <Card title="Quiet hours">
      <p style={muted}>
        {quiet ? `${quiet.from} to ${quiet.to}: check-ins wait until they end. Free time doesn't.` : 'None: a check-in fires at its time.'}
      </p>
      {onSet ? (
        <form
          aria-label="Set quiet hours"
          onSubmit={(event) => {
            event.preventDefault();
            if (from && to) onSet(from, to);
          }}
          style={row}
        >
          <TimeField label="From" value={from} onChange={setFrom} />
          <TimeField label="To" value={to} onChange={setTo} />
          <Button variant="primary" type="submit" disabled={!from || !to}>
            Set quiet hours
          </Button>
          {quiet ? (
            <Button type="button" variant="quiet" onClick={() => onSet(null, null)}>
              Clear quiet hours
            </Button>
          ) : null}
        </form>
      ) : null}
    </Card>
  );
}
