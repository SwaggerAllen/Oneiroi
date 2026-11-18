import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type HouseBeats, type HouseCheckin } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { allZones, deviceZone, isTime } from '../time/rules';
import * as css from '../time/time.css';
import { BEATS, CHECKINS, HOUSE, when } from './keys';

/**
 * The house's Time (screen:next-house), laid out as a resident's Rhythm
 * (the witness, 2026-11-16): the house's check-ins (gaia#41, seshat#75),
 * the beats as they stand (gaia#33 to #39), who is in the house, and the
 * house's own clock, chosen from the zones the browser knows.
 */
export function HouseTime() {
  const checkins = useQuery({ queryKey: CHECKINS, queryFn: api.houseCheckins });
  const beats = useQuery({ queryKey: BEATS, queryFn: api.householdBeats, refetchInterval: 60_000 });
  const zone = checkins.data?.zone ?? 'Etc/UTC';
  return (
    <ScrollArea label="Time">
      <div className={css.page}>
        {checkins.isPending && <p className={css.note}>Reading…</p>}
        {checkins.isError && <p className={css.note}>No household here yet.</p>}
        {checkins.data && (
          <>
            <p className={css.note}>Every time here is the house's, in {zone}.</p>
            <Checkins checkins={checkins.data.checkins} />
          </>
        )}
        {beats.data && <Now b={beats.data} />}
        {beats.data && <Members b={beats.data} />}
        {beats.data && beats.data.closed.length > 0 && <Closed b={beats.data} />}
        {checkins.data && <Zone zone={zone} />}
      </div>
    </ScrollArea>
  );
}

/** A write and what came of it, reading the house again after. */
function useHouseWrite<T>(fn: (v: T) => Promise<unknown>) {
  const queries = useQueryClient();
  return useMutation({ mutationFn: fn, onSuccess: () => queries.invalidateQueries({ queryKey: [...HOUSE] }) });
}

function Failed({ error }: { error: Error | null }) {
  return error ? <p className={css.note}>That didn't go through: {error.message}</p> : null;
}

const keyOf = (label: string) =>
  label
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);

function Checkins({ checkins }: { checkins: HouseCheckin[] }) {
  const [label, setLabel] = useState('');
  const [time, setTime] = useState('');
  const add = useHouseWrite(() => api.setHouseCheckin(keyOf(label), label.trim(), time));
  return (
    <section className={css.section} aria-label="House check-ins">
      <h2 className={css.headingWitness}>HOUSE CHECK-INS</h2>
      <p className={css.note}>
        Each opens a thread once a day at its time and wakes every resident at once, each with the words you set for her on her Rhythm. Her one answer waits on no turn;
        your reply wakes everyone again. Quiet hours do not hold them.
      </p>
      {checkins.length === 0 && <p className={css.note}>None set.</p>}
      {checkins.map((c) => (
        <Checkin key={c.key} c={c} />
      ))}
      <form
        className={css.addRow}
        aria-label="Add a house check-in"
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
        <button type="submit" className={css.addButton} disabled={!keyOf(label) || !isTime(time) || add.isPending}>
          Add a check-in
        </button>
      </form>
      <Failed error={add.error} />
    </section>
  );
}

function Checkin({ c }: { c: HouseCheckin }) {
  const [removing, setRemoving] = useState(false);
  const [note, setNote] = useState('');
  const remove = useHouseWrite(() => api.removeHouseCheckin(c.key, note.trim()));
  return (
    <div className={css.card}>
      <div className={css.cardHead}>
        <span>{c.label}</span>
        <span className={css.meta}>
          {c.time} · {c.last_day ? `last ${c.last_day}` : 'not run yet'}
        </span>
      </div>
      {removing ? (
        <form
          className={css.addRow}
          aria-label={`Remove ${c.label}`}
          onSubmit={(e) => {
            e.preventDefault();
            remove.mutate(undefined);
          }}
        >
          <input className={css.time} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Why remove it" aria-label="Why remove it" />
          <button type="submit" className={css.addButton} disabled={!note.trim() || remove.isPending}>
            Remove {c.label}
          </button>
          <button type="button" className={css.quiet} onClick={() => setRemoving(false)}>
            Keep it
          </button>
        </form>
      ) : (
        <div>
          <button type="button" className={css.quiet} onClick={() => setRemoving(true)}>
            Remove
          </button>
        </div>
      )}
      <Failed error={remove.error} />
    </div>
  );
}

function Now({ b }: { b: HouseBeats }) {
  const open = b.open_turn;
  return (
    <section className={css.section} aria-label="The beat now">
      <h2 className={css.heading}>THE BEAT NOW</h2>
      <p className={css.note}>
        Began {when(b.beat.top)}, sign-up closed {when(b.beat.signup_closes)}, ends {when(b.beat.ends)}. {b.beat.turns_fired === 1 ? '1 turn' : `${b.beat.turns_fired} turns`} so far.
      </p>
      <div className={open ? css.rowHers : css.row}>
        <span>{open ? `${open.name ?? 'A resident'} holds the turn` : 'No turn is open'}</span>
        {open && <span className={css.meta}>until {when(open.ends_by)}</span>}
      </div>
      {b.queue.map((q) => (
        <div key={q.resident_id} className={css.row}>
          <span>
            {q.position}. {q.name}
          </span>
          <span className={css.meta}>
            {q.turns_this_beat} this beat · {q.missed} missed
          </span>
        </div>
      ))}
      <p className={css.note}>
        Your posts: {b.you.quota_left} of {b.you.quota} left in {b.you.quota_window_hours} hours.
        {b.upcoming.length > 0 ? ` Next beats: ${b.upcoming.slice(0, 3).map((u) => when(u.top)).join(', ')}.` : ''}
      </p>
    </section>
  );
}

const PROFILES: Record<string, string> = {
  every_beat: 'a digest each beat',
  on_turn: 'woken on her turn',
  self: 'wakes herself',
};

function Members({ b }: { b: HouseBeats }) {
  return (
    <section className={css.section} aria-label="Who is in the house">
      <h2 className={css.heading}>WHO IS IN THE HOUSE</h2>
      {b.profiles.map((p) => (
        <div key={p.id} className={p.kind === 'resident' ? css.rowHers : css.row}>
          <span>{p.name}</span>
          <span className={css.meta}>
            {p.kind === 'witness' ? 'witness · never woken' : (PROFILES[p.profile] ?? p.profile)}
            {p.missed ? ` · ${p.missed} missed` : ''}
          </span>
        </div>
      ))}
    </section>
  );
}

function Closed({ b }: { b: HouseBeats }) {
  return (
    <section className={css.section} aria-label="Beats closed lately">
      <h2 className={css.heading}>BEATS CLOSED LATELY</h2>
      {b.closed.map((c) => (
        <div key={c.beat_top} className={css.row}>
          <span>{when(c.beat_top)}</span>
          <span className={css.meta}>
            {c.turns.length === 1 ? '1 turn' : `${c.turns.length} turns`}
            {c.passed_over.length ? ` · ${c.passed_over.length} passed over` : ''}
          </span>
        </div>
      ))}
    </section>
  );
}

function Zone({ zone }: { zone: string }) {
  const device = deviceZone();
  const [chosen, setChosen] = useState(zone);
  const set = useHouseWrite((tz: string) => api.setHouseClock(tz));
  return (
    <section className={css.section} aria-label="The house's time zone">
      <h2 className={css.heading}>THE HOUSE'S TIME ZONE</h2>
      <p className={css.note}>
        {zone}, whatever any resident's own.
        {device && device !== zone ? ` This device is in ${device}.` : ''}
      </p>
      <div className={css.addRow}>
        <select className={css.time} value={chosen} onChange={(e) => setChosen(e.target.value)} aria-label="Zone">
          {allZones(zone, device).map((z) => (
            <option key={z} value={z}>
              {z}
            </option>
          ))}
        </select>
        <button type="button" className={css.addButton} disabled={chosen === zone || set.isPending} onClick={() => set.mutate(chosen)}>
          Set the zone
        </button>
        {device && device !== zone && (
          <button type="button" className={css.quiet} onClick={() => set.mutate(device)}>
            Use {device}
          </button>
        )}
      </div>
      <Failed error={set.error} />
    </section>
  );
}
