import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useNow } from '../shell/presence';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { MONTHS, monthCells, shiftMonth } from './calendar';
import { Journal } from './Journal';
import { Rhythm } from './Rhythm';
import * as css from './time.css';

/**
 * Time (ui-structures.md D): a telescoping calendar, and Rhythm, which
 * holds the rules. The stack's top says which day is open
 * (`day/YYYY-MM-DD`); the month is the root.
 */
export function TimeTab({ path }: { path: string }) {
  const [view, setView] = useState<'calendar' | 'rhythm'>('calendar');
  return (
    <div className={css.tab}>
      <ToggleButtonGroup
        aria-label="Time view"
        selectionMode="single"
        disallowEmptySelection
        selectedKeys={[view]}
        onSelectionChange={(keys) => setView([...keys][0] as 'calendar' | 'rhythm')}
        className={css.switcher}
      >
        <ToggleButton id="calendar" className={css.option}>
          Calendar
        </ToggleButton>
        <ToggleButton id="rhythm" className={css.option}>
          Rhythm
        </ToggleButton>
      </ToggleButtonGroup>
      <div className={css.body}>
        <div className={css.pane} hidden={view !== 'calendar'}>
          {path.startsWith('day/') ? <Day day={path.slice(4)} /> : <Month />}
        </div>
        <div className={css.pane} hidden={view !== 'rhythm'}>
          <Rhythm />
        </div>
      </div>
    </div>
  );
}

function useToday(): string | undefined {
  const { id } = useSubject();
  const schedule = useQuery({ queryKey: ['resident', id, 'time', 'schedule'], queryFn: () => api.schedule(id) });
  return schedule.data?.day;
}

function Month() {
  const { id } = useSubject();
  const push = useShell((s) => s.push);
  const now = useNow(false);
  const today = useToday() ?? new Date(now).toISOString().slice(0, 10);
  const [shown, setShown] = useState(() => ({ year: Number(today.slice(0, 4)), month: Number(today.slice(5, 7)) }));
  const cells = monthCells(shown.year, shown.month);
  const from = cells.find((c) => c.day)?.day as string;
  const to = [...cells].reverse().find((c) => c.day)?.day as string;
  // One read for the month (sunna#48): her journal, the sessions and scenes, the schedule ahead.
  const range = useQuery({ queryKey: ['resident', id, 'time', 'days', from], queryFn: () => api.days(id, from, to) });
  const byDay = new Map((range.data?.days ?? []).map((d) => [d.day, d]));

  return (
    <ScrollArea label="Calendar">
      <div className={css.page}>
        <div className={css.monthHead}>
          <button type="button" className={css.nav} aria-label="Previous month" onClick={() => setShown((s) => shiftMonth(s.year, s.month, -1))}>
            ‹
          </button>
          <div className={css.monthTitle}>
            <span className={css.monthName}>{MONTHS[shown.month - 1]}</span>
            <span className={css.meta}>{shown.year}</span>
          </div>
          <button type="button" className={css.nav} aria-label="Next month" onClick={() => setShown((s) => shiftMonth(s.year, s.month, 1))}>
            ›
          </button>
        </div>
        <div className={css.weekdays} aria-hidden>
          {['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map((d) => (
            <span key={d}>{d}</span>
          ))}
        </div>
        <div className={css.grid} role="grid" aria-label={`${MONTHS[shown.month - 1]} ${shown.year}`}>
          {cells.map((c, i) => {
            if (!c.day) return <span key={`blank-${i}`} />;
            const d = byDay.get(c.day);
            const wrote = d?.journal != null;
            const spoken = (d?.story.sessions ?? []).filter(heldWords);
            const talked = spoken.length > 0;
            const scenes = (d?.story.scenes ?? []).filter((x) => x.kind === 'scene').length;
            const free = (d?.schedule?.entries ?? []).some((e) => e.kind === 'free_time');
            const dated = (d?.schedule?.entries ?? []).find((e) => e.kind === 'date');
            const says = [wrote && 'journal written', talked && `${spoken.length} sessions`, scenes > 0 && `${scenes} scenes`, free && 'free time', dated && (dated.label ?? 'a date')].filter(Boolean);
            return (
              <button
                key={c.day}
                type="button"
                className={css.cell}
                data-today={c.day === today}
                data-past={c.day < today}
                aria-label={`${c.day}${says.length ? `, ${says.join(', ')}` : ''}`}
                onClick={() => push(`day/${c.day}`)}
              >
                <span>{c.date}</span>
                <span className={css.marks} aria-hidden>
                  {wrote && <span className={css.journalDot} />}
                  {talked && <span className={css.sessionDot} />}
                  {scenes > 0 && <span className={css.sceneBar} style={{ width: Math.min(18, 4 + scenes * 3) }} />}
                  {free && <span className={css.freeDot} />}
                  {dated && <span className={css.dateMark} title={dated.label ?? undefined} />}
                </span>
              </button>
            );
          })}
        </div>
        <p className={css.note}>Lilac: she wrote in her journal. Blue: a session that day. A bar: her scenes that day. A ring: her free time ahead. A diamond: an important date.</p>
      </div>
    </ScrollArea>
  );
}

// A session opened and never spoken in carries nothing to read; a
// private one keeps its count back (null), so it stays.
const heldWords = (s: { messages: number | null }) => s.messages !== 0;

function Day({ day }: { day: string }) {
  const { id, name } = useSubject();
  const back = useShell((s) => s.back);
  const today = useToday();
  const one = useQuery({ queryKey: ['resident', id, 'time', 'day', day], queryFn: () => api.days(id, day, day).then((r) => r.days[0]) });
  // Her entries in full, only for a day the range says she wrote in.
  const journal = useQuery({
    queryKey: ['resident', id, 'time', 'journal', day],
    queryFn: () => api.journalDay(id, day).catch(() => ({ day, entries: [] })),
    enabled: one.data?.journal != null,
  });
  const all = one.data?.story.sessions ?? [];
  const that = all.filter(heldWords);
  const empty = all.length - that.length;
  const scenes = (one.data?.story.scenes ?? []).filter((x) => x.kind === 'scene');
  const ahead = one.data?.schedule;
  const clock = (iso: string | null) => (iso ? new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '');
  const label = new Date(`${day}T12:00:00`).toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });

  return (
    <ScrollArea label={day}>
      <div className={css.page}>
        <button type="button" className={css.back} onClick={back}>
          ‹ Month
        </button>
        <h1 className={css.dayTitle}>
          {label}
          {day === today && <span className={css.todayTag}> TODAY</span>}
        </h1>
        <Journal key={day} name={name} entries={journal.data?.entries ?? []} />
        {ahead && ahead.entries.length > 0 && (
          <section className={css.section}>
            <h2 className={css.heading}>{day === today ? 'STILL TO COME' : 'AS IT STANDS'}</h2>
            {ahead.entries
              .filter((e) => day !== today || new Date(e.at).getTime() > Date.now())
              .map((e) => (
                <div key={`${e.kind}-${e.key}`} className={e.kind === 'free_time' ? css.rowHers : css.row}>
                  <span>
                    {e.kind === 'free_time' ? 'Free time' : (e.label ?? e.kind)}
                    {e.deferred ? ' · after quiet hours' : ''}
                    {e.rule ? '' : ' · once'}
                  </span>
                  <span className={css.meta}>{e.time}</span>
                </div>
              ))}
            {ahead.rounds > 0 && <p className={css.note}>{`${name} has ${ahead.rounds} rounds of her own this day.`}</p>}
          </section>
        )}
        <section className={css.section}>
          <h2 className={css.headingHers}>
            SCENES · {scenes.length}
            {one.data?.story.complete === false ? ' · NOT FINISHED' : ''}
          </h2>
          {scenes.length === 0 && <p className={css.note}>{one.data?.journal === null && one.data?.story.complete === null ? 'No scenes for this day.' : 'No scenes yet.'}</p>}
          {scenes.map((x) => (
            <div key={x.number} className={css.rowHers}>
              <span>{x.title ?? 'Untitled'}</span>
              <span className={css.meta}>
                {clock(x.from_time)}
                {x.to_time ? `–${clock(x.to_time)}` : ''}
              </span>
            </div>
          ))}
        </section>
        <section className={css.section}>
          <h2 className={css.heading}>SESSIONS · {that.length}</h2>
          {that.length === 0 && <p className={css.note}>No conversation this day.</p>}
          {that.map((s) => (
            <div key={s.key} className={css.row}>
              <span>
                {s.title}
                {s.locked ? ' · private' : ''}
              </span>
              <span className={css.meta}>
                {clock(s.first_at)}–{clock(s.last_at)}
                {s.messages !== null ? ` · ${s.messages}` : ''}
              </span>
            </div>
          ))}
          {empty > 0 && <p className={css.note}>{empty === 1 ? 'One session opened and never spoken in is left out.' : `${empty} sessions opened and never spoken in are left out.`}</p>}
        </section>
      </div>
    </ScrollArea>
  );
}
