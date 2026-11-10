import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import type { Session } from '../../api/types';
import { ScrollArea } from '../shell/ScrollArea';
import { useNow } from '../shell/presence';
import { useShell } from '../state/store';
import * as css from './sessions.css';

function sameDay(iso: string | null, day: string): boolean {
  return !!iso && iso.slice(0, 10) === day;
}

function hhmm(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/**
 * Sessions (ui-structures.md D, the canvas's Sessions board): what is
 * running now, what is planned, and today's. Free time is listed as
 * running, never read: its words are hers.
 */
export function Sessions({ residentId, onConversation }: { residentId: string; onConversation: () => void }) {
  const sessions = useQuery({ queryKey: ['resident', residentId, 'sessions', 'list'], queryFn: () => api.sessions(residentId) });
  const schedule = useQuery({ queryKey: ['resident', residentId, 'sessions', 'schedule'], queryFn: () => api.schedule(residentId) });
  const presence = useShell((s) => s.presence);
  const nowMs = useNow(false);

  const day = schedule.data?.day ?? new Date(nowMs).toISOString().slice(0, 10);
  const now = schedule.data?.now ? schedule.data.now.slice(11, 16) : '';
  const recent = (s: Session) => s.last_turn_at !== null && nowMs - Date.parse(s.last_turn_at) < 10 * 60_000;
  const all = sessions.data ?? [];
  const running = all.filter((s) => (s.kind === 'main' ? presence.state !== 'idle' : recent(s)));
  const today = all
    .filter((s) => sameDay(s.last_turn_at, day) && !running.includes(s))
    .sort((a, b) => (b.last_turn_at ?? '').localeCompare(a.last_turn_at ?? ''));

  const planned: { label: string; when: string }[] = [];
  for (const c of schedule.data?.checkins ?? []) if (c.time > now) planned.push({ label: c.label, when: c.time });
  for (const f of schedule.data?.free_times ?? []) if (f.time > now) planned.push({ label: 'Free time', when: f.time });
  for (const o of schedule.data?.free_time_once ?? []) planned.push({ label: 'Free time (once)', when: `${o.day === day ? '' : o.day + ' '}${o.time}` });
  if (schedule.data?.next?.tomorrow) planned.push({ label: schedule.data.next.label, when: `tomorrow ${schedule.data.next.time}` });
  planned.sort((a, b) => a.when.localeCompare(b.when));

  return (
    <ScrollArea label="Sessions">
      <div className={css.page}>
        <section className={css.section}>
          <h2 className={css.headingLive}>RUNNING NOW</h2>
          {running.length === 0 && <p className={css.empty}>Nothing running.</p>}
          {running.map((s) => (
            <SessionRow key={s.key} s={s} live onOpen={s.kind === 'main' ? onConversation : undefined} />
          ))}
        </section>
        <section className={css.section}>
          <h2 className={css.heading}>PLANNED</h2>
          {planned.length === 0 && <p className={css.empty}>Nothing else today.</p>}
          {planned.map((p, i) => (
            <div key={`${p.label}-${i}`} className={css.row}>
              <span>{p.label}</span>
              <span className={css.when}>{p.when}</span>
            </div>
          ))}
        </section>
        <section className={css.section}>
          <h2 className={css.heading}>TODAY</h2>
          {today.length === 0 && <p className={css.empty}>No other conversations today.</p>}
          {today.map((s) => (
            <SessionRow key={s.key} s={s} onOpen={s.kind === 'main' ? onConversation : undefined} />
          ))}
        </section>
      </div>
    </ScrollArea>
  );
}

function SessionRow({ s, live, onOpen }: { s: Session; live?: boolean; onOpen?: () => void }) {
  const privateWords = s.kind === 'free_time' || /free time/i.test(s.title);
  const body = (
    <>
      <span className={css.title}>
        {live && <span className={css.dot} />}
        {s.title}
        {s.place && <span className={css.place}> · {s.place}</span>}
      </span>
      <span className={css.when}>
        {privateWords ? 'WORDS PRIVATE · ' : ''}
        {s.turns} TURNS{s.last_turn_at ? ` · ${hhmm(s.last_turn_at)}` : ''}
      </span>
    </>
  );
  return onOpen ? (
    <button type="button" className={css.rowButton} onClick={onOpen}>
      {body}
    </button>
  ) : (
    <div className={css.row}>{body}</div>
  );
}
