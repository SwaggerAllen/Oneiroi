import { useState } from 'react';
import { api, type HouseCheckin } from '../../api/client';
import { Card, Field, Said } from '../settings/common';
import * as css from '../settings/settings.css';
import { useAct } from '../settings/useAct';
import { CHECKINS as KEY } from './keys';

/**
 * The house's clock and its check-ins (gaia#41, seshat#75), on the house's
 * Time tab (screen:next-house). Each resident's own words for a check-in
 * are set on her Rhythm page.
 */
export function Clock({ zone }: { zone: string }) {
  const [value, setValue] = useState(zone);
  const act = useAct();
  return (
    <Card title="The house's clock">
      <p className={css.text}>House check-ins keep this clock, whatever any resident's own. Quiet hours do not hold them: those keep what reaches you.</p>
      <form
        aria-label="The house's clock"
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(() => api.setHouseClock(value.trim()).then(() => `The house keeps ${value.trim()}.`), KEY);
        }}
      >
        <Field label="Zone" value={value} onChange={(e) => setValue(e.target.value)} placeholder="America/Los_Angeles" />
        <button type="submit" className={css.primary} disabled={act.busy || !value.trim() || value.trim() === zone}>
          Set
        </button>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

export function Checkins({ checkins, zone }: { checkins: HouseCheckin[]; zone: string }) {
  const [label, setLabel] = useState('');
  const [time, setTime] = useState('');
  const act = useAct();
  const key = label
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
  return (
    <Card title="House check-ins">
      <p className={css.text}>
        Each fires once a day at its time on the house's clock ({zone}): it opens a thread in the shared workspace and wakes every resident at once, each with the words you set
        for her on her Rhythm page. Her one answer waits on no turn; your reply wakes everyone again, and from there the beats hold the talk.
      </p>
      {checkins.length === 0 && <p className={css.note}>None yet.</p>}
      <ul className={css.list} aria-label="House check-ins">
        {checkins.map((c) => (
          <Row key={c.key} c={c} />
        ))}
      </ul>
      <form
        aria-label="Add a house check-in"
        className={css.row}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(
            () =>
              api.setHouseCheckin(key, label.trim(), time).then(() => {
                setLabel('');
                setTime('');
                return 'Added.';
              }),
            KEY,
          );
        }}
      >
        <Field label="Label" value={label} maxLength={60} onChange={(e) => setLabel(e.target.value)} />
        <Field label="Time" type="time" value={time} onChange={(e) => setTime(e.target.value)} />
        <button type="submit" className={css.primary} disabled={act.busy || !key || !/^\d{2}:\d{2}$/.test(time)}>
          Add
        </button>
      </form>
      <Said said={act.said} />
    </Card>
  );
}

function Row({ c }: { c: HouseCheckin }) {
  const [note, setNote] = useState('');
  const act = useAct();
  return (
    <li className={css.item}>
      <p className={css.meta}>
        {c.label} · {c.time} · {c.last_day ? `last ${c.last_day}` : 'not run yet'}
      </p>
      <form
        className={css.row}
        aria-label={`Remove ${c.label}`}
        onSubmit={(e) => {
          e.preventDefault();
          void act.run(() => api.removeHouseCheckin(c.key, note.trim()).then(() => 'Removed.'), KEY);
        }}
      >
        <Field label="Why remove it" value={note} onChange={(e) => setNote(e.target.value)} />
        <button type="submit" className={css.quiet} disabled={act.busy || !note.trim()}>
          Remove
        </button>
      </form>
      <Said said={act.said} />
    </li>
  );
}
