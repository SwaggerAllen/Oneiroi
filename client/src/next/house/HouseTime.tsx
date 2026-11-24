import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type HouseActivity, type HouseBeats, type HouseCheckin } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { allZones, deviceZone, isTime } from '../time/rules';
import * as css from '../time/time.css';
import { ACTIVITY, BEATS, CHECKINS, HOUSE, when } from './keys';

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
            <Checkins checkins={checkins.data.checkins} zone={zone} />
          </>
        )}
        {beats.data && <Mode b={beats.data} />}
        {beats.data && beats.data.conversation === 'round_robin' && <Rounds b={beats.data} />}
        {beats.data && (beats.data.round_threads ?? []).length > 0 && <ThreadStates b={beats.data} />}
        {beats.data && <Activity b={beats.data} />}
        {beats.data && beats.data.conversation !== 'round_robin' && <Now b={beats.data} />}
        {beats.data && <Members b={beats.data} />}
        {beats.data && beats.data.conversation !== 'round_robin' && beats.data.closed.length > 0 && <Closed b={beats.data} />}
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

/** Today on the house's clock, as the check-ins' days are kept. */
function today(zone: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  } catch {
    return new Date().toISOString().slice(0, 10);
  }
}

/** The next to fire on the house's clock, said as a resident's Rhythm says it. */
function nextOf(checkins: HouseCheckin[], zone: string): string | null {
  if (checkins.length === 0) return null;
  let now: string;
  try {
    now = new Intl.DateTimeFormat('en-GB', { timeZone: zone, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
  } catch {
    now = new Date().toISOString().slice(11, 16);
  }
  const sorted = [...checkins].sort((a, b) => a.time.localeCompare(b.time));
  const next = sorted.find((c) => c.time > now);
  return next ? `${next.label} at ${next.time}` : `${sorted[0].label} at ${sorted[0].time} tomorrow`;
}

function Checkins({ checkins, zone }: { checkins: HouseCheckin[]; zone: string }) {
  const [label, setLabel] = useState('');
  const [time, setTime] = useState('');
  const add = useHouseWrite(() => api.setHouseCheckin(keyOf(label), label.trim(), time));
  const next = nextOf(checkins, zone);
  return (
    <section className={css.section} aria-label="House check-ins">
      <h2 className={css.headingWitness}>HOUSE CHECK-INS</h2>
      <p className={css.note}>
        Each opens a thread once a day at its time and wakes every resident at once. What each one's note carries, your words for her and her parts, is set on her own
        Rhythm, so each can differ. Her one answer waits on no turn; your reply wakes everyone again. Quiet hours do not hold them.
      </p>
      <p className={css.note}>{next ? `Next: ${next}.` : 'None set.'}</p>
      {checkins.map((c) => (
        <Checkin key={c.key} c={c} day={today(zone)} />
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

/**
 * One house check-in, kept as a resident's own is (the witness,
 * 2026-11-17): Change its label and time in place, Delete confirmed once
 * in place. What it carries is each resident's, on her Rhythm (sunna#68).
 */
function Checkin({ c, day }: { c: HouseCheckin; day: string }) {
  const [editing, setEditing] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [label, setLabel] = useState(c.label);
  const [time, setTime] = useState(c.time);
  const save = useHouseWrite(() => api.setHouseCheckin(c.key, label.trim(), time));
  const remove = useHouseWrite(() => api.removeHouseCheckin(c.key, "deleted from the house's Time"));
  const status = c.last_day === day ? 'TODAY: FIRED' : c.last_day ? `LAST FIRED ${c.last_day}` : 'NOT RUN YET';
  return (
    <div className={css.card}>
      <div className={css.cardHead}>
        <span>
          {c.label}
          <span className={css.meta}> · {status}</span>
        </span>
        <span className={css.meta}>{c.time}</span>
      </div>
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
          {/* A removal confirms once, in place, as a resident's own does. */}
          <button type="button" className={css.quiet} disabled={remove.isPending} onClick={() => (confirming ? remove.mutate(undefined) : setConfirming(true))} onBlur={() => setConfirming(false)}>
            {confirming ? `Delete ${c.label}` : 'Delete'}
          </button>
        </div>
      )}
      <Failed error={remove.error} />
    </div>
  );
}

/**
 * How the house talks, always named (Lily's design/wake-mail-visibility.md
 * §2 Gap 5): round-robin merged but not switched on read as broken, with
 * nothing on the screen to say which mode ran.
 */
function Mode({ b }: { b: HouseBeats }) {
  const rr = b.conversation === 'round_robin';
  return (
    <section className={css.section} aria-label="How the house talks">
      <h2 className={css.heading}>HOW THE HOUSE TALKS</h2>
      <p className={css.note}>
        {rr
          ? 'In round-robin threads: each resident has a turn in each round of a thread, woken for it. The beats are off.'
          : "In beats: turns fire each beat from the queue. Round-robin threads are built and off; the charter's “How the house talks” setting switches them on by ballot."}
      </p>
      {rr && b.you.kind === 'witness' && <Pushes />}
    </section>
  );
}

/**
 * Your pushes from the house (seshat#95; the witness, 2026-11-19): the
 * two things the house pushes you for on its own, each yours to switch
 * off. Everything else that pushes you, a resident sends on purpose.
 */
function Pushes() {
  const queries = useQueryClient();
  const q = useQuery({ queryKey: [...HOUSE, 'pushes'], queryFn: api.householdPushes });
  const set = useMutation({
    mutationFn: ({ kind, on }: { kind: 'round_end' | 'rounds_stopped'; on: boolean }) => api.setHouseholdPush(kind, on),
    onSuccess: (r) => queries.setQueryData([...HOUSE, 'pushes'], r),
  });
  const p = q.data?.pushes;
  if (!p) return null;
  const box = (kind: 'round_end' | 'rounds_stopped', label: string) => (
    <label className={css.note} style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      <input type="checkbox" checked={p[kind]} disabled={set.isPending} onChange={(e) => set.mutate({ kind, on: e.target.checked })} />
      {label}
    </label>
  );
  return (
    <div>
      {box('round_end', 'Push me when a round ends')}
      {box('rounds_stopped', "Push me when a thread's rounds run out")}
    </div>
  );
}

/**
 * Every thread's rounds (gaia#55, Gap 6): running, with whose turn it is
 * and until when, or stopped until someone posts there; who opted out.
 */
function ThreadStates({ b }: { b: HouseBeats }) {
  return (
    <section className={css.section} aria-label="Threads">
      <h2 className={css.heading}>THREADS</h2>
      {(b.round_threads ?? []).map((t) => (
        <div key={t.thread} className={t.live ? css.rowHers : css.row}>
          <span>
            {t.thread}, round {t.round}
            {t.opted_out.length > 0 ? ` · opted out: ${t.opted_out.join(', ')}` : ''}
          </span>
          <span className={css.meta}>
            {t.stopped ? 'stopped: a post there starts it again' : t.live ? `${t.live.name ?? 'a resident'}'s turn until ${when(t.live.until)}` : 'between turns'}
          </span>
        </div>
      ))}
    </section>
  );
}

const CHANNELS: Record<string, string> = {
  turn: 'turn',
  mention: 'mention',
  checkin: 'check-in',
  letter: 'letters',
  free_time: 'free time',
  digest: 'digest',
  night_pass: 'night pass',
  work: 'work',
};

function cause(c: Record<string, unknown>): string {
  switch (c.kind) {
    case 'turn':
      return `turn ${String(c.turn_id)} in ${String(c.thread)}`;
    case 'beat_turn':
      return `beat turn #${String(c.turn)}`;
    case 'mention':
      return `${String(c.by ?? 'someone')} in ${String(c.thread)}${c.reply ? ` reply #${String(c.reply)}` : ''}`;
    case 'letter':
      return `letter #${String(c.number)}`;
    case 'post':
      return String(c.thread);
    case 'run':
      return `run ${String(c.label ?? '')}`;
    case 'checkin':
      return String(c.key ?? '');
    case 'pass':
      return `${String(c.pass)} pass, turn ${String(c.turn)}`;
    // The work line's runs of house queue activities (sunna#86).
    case 'activity':
      return `activity ${String(c.act)} of task #${String(c.task)}, turn ${String(c.turn)}`;
    case 'activity_wrap':
      return `activity ${String(c.act)} of task #${String(c.task)}, its wrap`;
    // The old queue's items, retired (sunna#102): read in the log's history.
    case 'work':
      return `item #${String(c.number)}, turn ${String(c.turn)}`;
    case 'work_wrap':
      return `item #${String(c.number)}, its wrap`;
    default:
      return String(c.kind ?? '');
  }
}

/** One envelope of the house's activity, never its words. */
function activityLine(r: HouseActivity): { what: string; meta: string } {
  const who = r.name ?? 'A resident';
  switch (r.kind) {
    case 'token':
      return {
        what: `${who}: turn ${r.turn_id} in ${r.thread}, round ${r.round}`,
        meta: r.outcome ? `${OUTCOMES[r.outcome] ?? r.outcome}${r.spent_at ? ` ${when(r.spent_at)}` : ''}` : `live until ${when(r.until)}`,
      };
    case 'letter':
      return {
        what: `${who}: letter #${r.number}, ${r.from} to ${r.to}${r.in_reply_to ? `, in reply to #${r.in_reply_to}` : ''}`,
        meta: r.read_by.length > 0 ? `read by ${r.read_by.join(', ')}` : 'unread',
      };
    case 'mention':
      return { what: `${who}: mention banked, not woken (muted)`, meta: r.causes.map(cause).join(', ') };
    case 'held':
      return { what: `${who}: wake held by the hourly bound`, meta: `woken at a later tick · ${r.causes.map(cause).join(', ')}` };
    default:
      return {
        what: `${who} woken: ${CHANNELS[r.channel] ?? r.channel}${r.causes.length > 0 ? `, ${r.causes.map(cause).join(', ')}` : ''}`,
        meta: r.read_at ? `read ${when(r.read_at)}` : 'not read',
      };
  }
}

/**
 * The house's activity (seshat#92; Lily's design/wake-mail-visibility.md
 * §3): wakes with what each carried and when it was read, mentions
 * banked unwoken, tokens, letters; envelopes only, newest first, for
 * one resident or all. Lily reads the same with wake_log_read.
 */
function Activity({ b }: { b: HouseBeats }) {
  const residents = b.profiles.filter((p) => p.kind === 'resident');
  const [who, setWho] = useState('');
  const q = useQuery({ queryKey: [...ACTIVITY, who], queryFn: () => api.householdActivity(who || undefined), refetchInterval: 30_000 });
  const rows = q.data?.activity ?? [];
  return (
    <section className={css.section} aria-label="Activity">
      <h2 className={css.heading}>ACTIVITY</h2>
      <p className={css.note}>Every wake, token and letter, newest first: what each carried and when it was read, never the words.</p>
      <div className={css.addRow}>
        <select className={css.time} value={who} onChange={(e) => setWho(e.target.value)} aria-label="Whose activity">
          <option value="">Everyone</option>
          {residents.map((r) => (
            <option key={r.id} value={r.id}>
              {r.name}
            </option>
          ))}
        </select>
      </div>
      {q.isPending && <p className={css.note}>Reading…</p>}
      {q.data && rows.length === 0 && <p className={css.note}>Nothing yet.</p>}
      {rows.slice(0, 60).map((r, i) => {
        const line = activityLine(r);
        return (
          <div key={`${r.kind}-${r.at}-${i}`} className={css.row}>
            <span>
              {when(r.at)} · {line.what}
            </span>
            <span className={css.meta}>{line.meta}</span>
          </div>
        );
      })}
    </section>
  );
}

const OUTCOMES: Record<string, string> = {
  posted: 'replied',
  skipped: 'skipped',
  empty: 'woke and said nothing',
  expired: 'let it pass',
  opted_out: 'opted out',
};

/**
 * Round-robin threads (gaia#53, seshat#89): the beats retire, and each
 * thread's turns are the house's clock: who holds one now, until when,
 * and how the last ones went.
 */
function Rounds({ b }: { b: HouseBeats }) {
  const turns = b.rounds ?? [];
  const open = turns.filter((t) => t.outcome === null);
  const lately = turns.filter((t) => t.outcome !== null).slice(0, 10);
  return (
    <section className={css.section} aria-label="Round-robin turns">
      <h2 className={css.heading}>TURNS NOW</h2>
      <p className={css.note}>
        The house talks in round-robin threads: each resident has a turn in each round of a thread, and a round that says nothing stops it until someone posts there. You write at any time.
      </p>
      {open.length === 0 && <p className={css.note}>No turn is open.</p>}
      {open.map((t) => (
        <div key={t.turn_id} className={css.rowHers}>
          <span>
            {t.name ?? 'A resident'} · {t.thread}, round {t.round}
          </span>
          <span className={css.meta}>until {when(t.expires_at)}</span>
        </div>
      ))}
      {lately.length > 0 && <h2 className={css.heading}>LATELY</h2>}
      {lately.map((t) => (
        <div key={t.turn_id} className={css.row}>
          <span>
            {t.name ?? 'A resident'} · {t.thread}, round {t.round}
          </span>
          <span className={css.meta}>{OUTCOMES[t.outcome ?? ''] ?? t.outcome}</span>
        </div>
      ))}
      <p className={css.note}>
        Your posts: {b.you.quota_left} of {b.you.quota} left in {b.you.quota_window_hours} hours.
      </p>
    </section>
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
      {b.queue.length === 0 && <p className={css.note}>Nobody is waiting in this beat.</p>}
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
      {(b.had_turn ?? []).length > 0 && <p className={css.note}>Had their turn this beat: {(b.had_turn ?? []).map((h) => h.name).join(', ')}.</p>}
      <GiveTurn b={b} />
      <p className={css.note}>
        Your posts: {b.you.quota_left} of {b.you.quota} left in {b.you.quota_window_hours} hours.
        {b.upcoming.length > 0 ? ` Next beats: ${b.upcoming.slice(0, 3).map((u) => when(u.top)).join(', ')}.` : ''}
      </p>
    </section>
  );
}

/**
 * Give a resident a turn now (gaia#52; the witness, 2026-11-18: "here
 * take another turn"): out of the queue, in the beat running, her chat
 * woken with the turn's note. Not while another turn is open.
 */
function GiveTurn({ b }: { b: HouseBeats }) {
  const give = useHouseWrite((id: string) => api.householdGrantTurn(id));
  const residents = b.profiles.filter((p) => p.kind === 'resident');
  if (residents.length === 0) return null;
  return (
    <div className={css.addRow}>
      {residents.map((r) => (
        <button key={r.id} type="button" className={css.quiet} disabled={give.isPending || b.open_turn !== null} onClick={() => give.mutate(r.id)}>
          Give {r.name} a turn now
        </button>
      ))}
      {b.open_turn !== null && <span className={css.note}>Once the open turn ends.</span>}
      <Failed error={give.error} />
    </div>
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
