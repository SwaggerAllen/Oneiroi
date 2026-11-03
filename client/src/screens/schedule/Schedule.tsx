import { useState } from 'react';
import type { FreeTimeSlot, ScheduleCheckin, ScheduleToday } from '../../api/types';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { TimeField } from '../../components/TimeField';
import { TopBar } from '../../components/TopBar';

export interface ScheduleProps {
  residentName: string;
  today: ScheduleToday;
  onSetFreeTime?: (times: string[]) => void;
  onAddCheckin?: (label: string, time: string) => void;
  onDeleteCheckin?: (key: string) => void;
  onSetQuietHours?: (from: string | null, to: string | null) => void;
  // Sets the resident's zone, the one every time here is read in.
  onSetTimezone?: (timezone: string) => void;
}

// The bound sunna #22 sets: free time is one to four slots a day.
const SLOTS = 4;

const muted = { margin: 0, fontSize: 15, color: 'var(--ink-muted)' } as const;
const row = { display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' } as const;

// Schedule (spec §10, screens/schedule.md): today in the resident's zone,
// free time's slots with what each did today, the check-ins with their
// last firings, quiet hours and the dates. Every time is HH:MM where the
// resident lives, never the reader's.
export function Schedule({ residentName, today, onSetFreeTime, onAddCheckin, onDeleteCheckin, onSetQuietHours, onSetTimezone }: ScheduleProps) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Schedule" line={`${today.day} · times in ${residentName}'s zone, ${today.timezone}`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Zone residentName={residentName} timezone={today.timezone} onSet={onSetTimezone} />
        <FreeTime residentName={residentName} slots={today.free_times} onSet={onSetFreeTime} />
        <Checkins today={today} onAdd={onAddCheckin} onDelete={onDeleteCheckin} />
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

// Free time is part of the standard of care (sunna #21): its slots move,
// and the last one cannot be taken away, so there is no remove button on
// a list of one and no way to save an empty list.
function FreeTime({ residentName, slots, onSet }: { residentName: string; slots: FreeTimeSlot[]; onSet?: (times: string[]) => void }) {
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
    </Card>
  );
}

function Checkins({ today, onAdd, onDelete }: { today: ScheduleToday; onAdd?: (label: string, time: string) => void; onDelete?: (key: string) => void }) {
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
            <Checkin key={c.key} checkin={c} today={fired.get(c.key) ?? null} onDelete={onDelete} />
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
function Checkin({ checkin, today, onDelete }: { checkin: ScheduleCheckin; today: string | null; onDelete?: (key: string) => void }) {
  const [confirming, setConfirming] = useState(false);
  return (
    <li style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 'var(--space-2)', fontSize: 15 }}>
      <span>
        <strong style={{ fontWeight: 600 }}>{checkin.time}</strong> {checkin.label}{' '}
        <span style={{ color: 'var(--ink-muted)' }}>· {today ? `today: ${today}` : checkin.last_day ? `last ${checkin.last_outcome} ${checkin.last_day}` : 'not run yet'}</span>
      </span>
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
    </li>
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
