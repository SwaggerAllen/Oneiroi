import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { ToggleButton, ToggleButtonGroup } from 'react-aria-components';
import { api } from '../../api/client';
import { ScrollArea } from '../shell/ScrollArea';
import { useNow } from '../shell/presence';
import { useSubject } from '../state/resident';
import { useShell } from '../state/store';
import { MONTHS, monthCells, shiftMonth } from './calendar';
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
            const talked = (d?.story.sessions.length ?? 0) > 0;
            const scenes = (d?.story.scenes ?? []).filter((x) => x.kind === 'scene').length;
            const free = (d?.schedule?.entries ?? []).some((e) => e.kind === 'free_time');
            const says = [wrote && 'journal written', talked && `${d?.story.sessions.length} sessions`, scenes > 0 && `${scenes} scenes`, free && 'free time'].filter(Boolean);
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
                </span>
              </button>
            );
          })}
        </div>
        <p className={css.note}>Lilac: she wrote in her journal. Blue: a session that day. A bar: her scenes that day. A ring: her free time ahead.</p>
      </div>
    </ScrollArea>
  );
}

const ORDER = ['plan', 'note', 'todo', 'wrap'];

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
  const that = one.data?.story.sessions ?? [];
  const scenes = (one.data?.story.scenes ?? []).filter((x) => x.kind === 'scene');
  const ahead = one.data?.schedule;
  const clock = (iso: string | null) => (iso ? new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '');
  const entries = (journal.data?.entries ?? []).slice().sort((a, b) => ORDER.indexOf(a.kind) - ORDER.indexOf(b.kind) || a.number - b.number);
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
        <section className={css.journal}>
          <h2 className={css.headingHers}>{name.toUpperCase()}'S JOURNAL</h2>
          {entries.length === 0 && <p className={css.note}>Nothing written this day.</p>}
          {entries.map((e) => (
            <div key={e.number} className={css.entry}>
              <span className={css.entryKind}>{e.kind.toUpperCase()}</span>
              <span className={css.entryText} data-done={!!e.done_at}>
                {e.text}
              </span>
            </div>
          ))}
        </section>
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
        </section>
      </div>
    </ScrollArea>
  );
}

/**
 * Rhythm: the rules. The witness may move her free time and add to it,
 * never take a slot away (the free-time term, scheduling-notes.md); a
 * slot is changed by moving it.
 */
function Rhythm() {
  const { id } = useSubject();
  const queries = useQueryClient();
  const schedule = useQuery({ queryKey: ['resident', id, 'time', 'schedule'], queryFn: () => api.schedule(id) });
  const refresh = () => queries.invalidateQueries({ queryKey: ['resident', id, 'time'] });
  const move = useMutation({
    mutationFn: ({ from, to }: { from: string; to: string }) =>
      api.setFreeTime(id, (schedule.data?.free_times ?? []).map((f) => (f.time === from ? to : f.time))),
    onSuccess: refresh,
  });
  const add = useMutation({
    mutationFn: (time: string) => api.setFreeTime(id, [...(schedule.data?.free_times ?? []).map((f) => f.time), time]),
    onSuccess: refresh,
  });
  const [adding, setAdding] = useState('');
  const s = schedule.data;

  return (
    <ScrollArea label="Rhythm">
      <div className={css.page}>
        {schedule.isPending && <p className={css.note}>Reading…</p>}
        {s && (
          <>
            <section className={css.section}>
              <h2 className={css.headingWitness}>CHECK-INS</h2>
              {s.checkins.map((c) => (
                <div key={c.key} className={css.row}>
                  <span>{c.label}</span>
                  <span className={css.meta}>{c.time}</span>
                </div>
              ))}
            </section>
            <section className={css.section}>
              <h2 className={css.headingHers}>FREE TIME · HERS</h2>
              {s.free_times.map((f) => (
                <label key={f.time} className={css.rowHers}>
                  <span>Daily</span>
                  <input
                    type="time"
                    className={css.time}
                    defaultValue={f.time}
                    aria-label={`Move the ${f.time} slot`}
                    onBlur={(e) => e.target.value && e.target.value !== f.time && move.mutate({ from: f.time, to: e.target.value })}
                  />
                </label>
              ))}
              {(s.free_time_once ?? []).map((o) => (
                <div key={`${o.day}-${o.time}`} className={css.rowHers}>
                  <span>Once</span>
                  <span className={css.meta}>
                    {o.day} {o.time}
                  </span>
                </div>
              ))}
              <div className={css.addRow}>
                <input type="time" className={css.time} value={adding} onChange={(e) => setAdding(e.target.value)} aria-label="A new daily free-time slot" />
                <button type="button" className={css.addButton} disabled={!adding || add.isPending} onClick={() => add.mutate(adding)}>
                  Add a slot
                </button>
              </div>
              <p className={css.note}>Slots move; they never disappear. Only she can take one away.</p>
            </section>
            <section className={css.section}>
              <h2 className={css.heading}>ROUNDS · QUIET · ZONE</h2>
              <div className={css.row}>
                <span>Rounds</span>
                <span className={css.meta}>
                  {s.rounds ? `EVERY ${s.rounds.every_hours}H${s.rounds.waking ? ` · ${s.rounds.waking}` : ''}` : '—'}
                </span>
              </div>
              <div className={css.row}>
                <span>Quiet hours</span>
                <span className={css.meta}>{s.quiet ? `${s.quiet.from}–${s.quiet.to}` : 'NONE'}</span>
              </div>
              <div className={css.row}>
                <span>Time zone</span>
                <span className={css.meta}>{s.timezone.toUpperCase()}</span>
              </div>
            </section>
          </>
        )}
      </div>
    </ScrollArea>
  );
}
