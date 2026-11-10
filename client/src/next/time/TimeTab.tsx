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
  const journal = useQuery({ queryKey: ['resident', id, 'time', 'journal-days'], queryFn: () => api.journalDays(id) });
  const written = new Set((journal.data ?? []).map((d) => d.day));

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
          {monthCells(shown.year, shown.month).map((c, i) =>
            c.day ? (
              <button
                key={c.day}
                type="button"
                className={css.cell}
                data-today={c.day === today}
                data-past={c.day < today}
                aria-label={`${c.day}${written.has(c.day) ? ', journal written' : ''}`}
                onClick={() => push(`day/${c.day}`)}
              >
                <span>{c.date}</span>
                {written.has(c.day) && <span className={css.journalDot} />}
              </button>
            ) : (
              <span key={`blank-${i}`} />
            ),
          )}
        </div>
        <p className={css.note}>A lilac dot is a day she wrote in her journal. Scene and session marks arrive with the calendar ranges (S5).</p>
      </div>
    </ScrollArea>
  );
}

const ORDER = ['plan', 'note', 'todo', 'wrap'];

function Day({ day }: { day: string }) {
  const { id, name } = useSubject();
  const back = useShell((s) => s.back);
  const today = useToday();
  const journal = useQuery({
    queryKey: ['resident', id, 'time', 'journal', day],
    queryFn: () => api.journalDay(id, day).catch(() => ({ day, entries: [] })),
  });
  const sessions = useQuery({ queryKey: ['resident', id, 'sessions', 'list'], queryFn: () => api.sessions(id) });
  const schedule = useQuery({ queryKey: ['resident', id, 'time', 'schedule'], queryFn: () => api.schedule(id), enabled: day === today });
  const that = (sessions.data ?? []).filter((s) => s.last_turn_at?.slice(0, 10) === day || s.opened_at.slice(0, 10) === day);
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
        {day === today && schedule.data && (
          <section className={css.section}>
            <h2 className={css.heading}>STILL TO COME</h2>
            {schedule.data.checkins
              .filter((c) => c.time > schedule.data.now.slice(11, 16))
              .map((c) => (
                <div key={c.key} className={css.row}>
                  <span>{c.label}</span>
                  <span className={css.meta}>{c.time}</span>
                </div>
              ))}
            {schedule.data.free_times
              .filter((f) => f.time > schedule.data.now.slice(11, 16))
              .map((f) => (
                <div key={f.time} className={css.rowHers}>
                  <span>Free time</span>
                  <span className={css.meta}>{f.time}</span>
                </div>
              ))}
          </section>
        )}
        <section className={css.section}>
          <h2 className={css.heading}>SESSIONS · {that.length}</h2>
          {that.map((s) => (
            <div key={s.key} className={css.row}>
              <span>{s.title}</span>
              <span className={css.meta}>{s.turns} TURNS</span>
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
