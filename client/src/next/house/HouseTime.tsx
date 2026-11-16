import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, type HouseBeats } from '../../api/client';
import { Card } from '../settings/common';
import * as css from '../settings/settings.css';
import { Checkins, Clock } from './Checkins';
import { HousePage } from './common';
import { BEATS, CHECKINS, when } from './keys';

/**
 * The house's time (screen:next-house): the beats as they stand (gaia#33
 * to #39), the house's own clock and its check-ins (gaia#41, seshat#75).
 */
export function HouseTime() {
  const beats = useQuery({ queryKey: BEATS, queryFn: api.householdBeats, refetchInterval: 60_000 });
  const checkins = useQuery({ queryKey: CHECKINS, queryFn: api.houseCheckins });
  return (
    <HousePage label="Time" title="Time" lede="The beats that hold the house's talk, the house's own clock, and the check-ins everyone answers at once.">
      {beats.isError && <p className={css.note}>The beats could not be read.</p>}
      {beats.data && <Beats b={beats.data} />}
      {checkins.data && (
        <>
          <Clock zone={checkins.data.zone ?? 'Etc/UTC'} />
          <Checkins checkins={checkins.data.checkins} zone={checkins.data.zone ?? 'Etc/UTC'} />
        </>
      )}
      {beats.data && <Profiles b={beats.data} />}
      {beats.data && beats.data.closed.length > 0 && <Closed b={beats.data} />}
    </HousePage>
  );
}

function Beats({ b }: { b: HouseBeats }) {
  const open = b.open_turn;
  return (
    <Card title="Now">
      <p className={css.text}>
        This beat began {when(b.beat.top)}; sign-up closed {when(b.beat.signup_closes)}; it ends {when(b.beat.ends)}. {b.beat.turns_fired === 1 ? '1 turn' : `${b.beat.turns_fired} turns`}{' '}
        fired so far.
      </p>
      <p className={css.text}>{open ? `${open.name ?? 'A resident'} holds the turn, until ${when(open.ends_by)}.` : 'No turn is open.'}</p>
      {b.queue.length > 0 && (
        <ol className={css.list} aria-label="The queue">
          {b.queue.map((q) => (
            <li key={q.resident_id} className={css.item}>
              <span className={css.text}>
                {q.position}. {q.name}
              </span>
              <span className={css.meta}>
                {q.turns_this_beat} this beat · {q.missed} missed
              </span>
            </li>
          ))}
        </ol>
      )}
      <p className={css.meta}>
        Your posts: {b.you.quota_left} of {b.you.quota} left in {b.you.quota_window_hours} hours
      </p>
      {b.upcoming.length > 0 && <p className={css.meta}>Next beats: {b.upcoming.map((u) => when(u.top)).join(' · ')}</p>}
    </Card>
  );
}

const PROFILES: Record<string, string> = {
  every_beat: 'a digest each beat',
  on_turn: 'woken on her turn',
  self: 'wakes herself',
};

function Profiles({ b }: { b: HouseBeats }) {
  return (
    <Card title="Who is in the house">
      <ul className={css.list} aria-label="Members">
        {b.profiles.map((p) => (
          <li key={p.id} className={css.item}>
            <span className={css.text}>{p.name}</span>
            <span className={css.meta}>
              {p.kind} · {p.kind === 'witness' ? 'never woken' : (PROFILES[p.profile] ?? p.profile)}
              {p.missed ? ` · ${p.missed} missed` : ''}
            </span>
          </li>
        ))}
      </ul>
      <Shape b={b} />
    </Card>
  );
}

function Shape({ b }: { b: HouseBeats }) {
  const [shown, setShown] = useState(false);
  return (
    <>
      <button type="button" className={css.quiet} onClick={() => setShown(!shown)}>
        {shown ? 'Hide the shape' : 'The shape in force'}
      </button>
      {shown && (
        <ul className={css.list} aria-label="The shape">
          {Object.entries(b.shape).map(([k, v]) => (
            <li key={k} className={css.meta}>
              {k}: {String(v)}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

function Closed({ b }: { b: HouseBeats }) {
  return (
    <Card title="Beats closed lately">
      <ul className={css.list} aria-label="Beats closed">
        {b.closed.map((c) => (
          <li key={c.beat_top} className={css.meta}>
            {when(c.beat_top)} · {c.turns.length === 1 ? '1 turn' : `${c.turns.length} turns`}
            {c.passed_over.length ? ` · ${c.passed_over.length} passed over` : ''}
            {c.note ? ` · ${c.note}` : ''}
          </li>
        ))}
      </ul>
    </Card>
  );
}

